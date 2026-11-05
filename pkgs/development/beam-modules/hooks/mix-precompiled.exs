defmodule Nix.SCM do
  @behaviour Mix.SCM

  @dependencies System.fetch_env!("MIX_NIX_DEPS")
                |> File.read!()
                |> String.split("\n", trim: true)
                |> Map.new(fn line ->
                  [name, source, artifact] = String.split(line, "\t")
                  {name, {source, artifact}}
                end)

  @impl Mix.SCM
  def fetchable?, do: false

  @impl Mix.SCM
  def accepts_options(app, opts) do
    case Map.get(@dependencies, Atom.to_string(app)) do
      {source, artifact} ->
        if opts[:in_umbrella] do
          nil
        else
          scm =
            cond do
              opts[:path] -> Mix.SCM.Path
              opts[:git] || opts[:github] -> Mix.SCM.Git
              true -> Hex.SCM
            end

          if scm == Hex.SCM, do: Mix.Hex.start()
          original = apply(scm, :accepts_options, [app, opts])

          original
          |> Keyword.put(:dest, source)
          |> Keyword.put(:compile, false)
          |> Keyword.put(:nix_scm, scm)
          |> Keyword.put(:nix_app, app)
          |> Keyword.put(:nix_artifact, artifact)
          |> Keyword.put(:nix_original, original)
        end

      nil ->
        nil
    end
  end

  @impl Mix.SCM
  def checked_out?(opts) do
    reject_force!(opts)
    artifact = opts[:nix_artifact]
    app = opts[:nix_app]

    properties =
      case :file.consult(Path.join([artifact, "ebin", "#{app}.app"])) do
        {:ok, [{:application, ^app, properties}]} -> properties
        _ -> Mix.raise("Invalid Nix precompiled application #{app}: missing or invalid .app file")
      end

    compile_env = properties[:compile_env] || []

    unless Config.Provider.valid_compile_env?(compile_env) do
      Mix.raise("Nix precompiled dependency #{app} has incompatible compile-time configuration")
    end

    validate_toolchain!(opts)
    lock = Mix.Dep.Lock.read()[app]
    validate_lock!(Keyword.put(opts, :lock, lock))
    prepare_build!(opts)
    true
  end

  @impl Mix.SCM
  def lock_status(opts) do
    validate_lock!(opts)
    :ok
  end

  defp validate_lock!(opts) do
    opts = resolve_lock(opts)
    scm = opts[:nix_scm]
    source_opts = Keyword.put(opts, :checkout, opts[:dest])

    if scm == Hex.SCM do
      name = opts[:hex]
      repo = opts[:repo]

      case apply(Hex.Utils, :lock, [opts[:lock]]) do
        %{name: ^name, repo: ^repo} ->
          :ok

        _ ->
          Mix.raise(
            "Nix precompiled dependency #{opts[:nix_app]} has an incompatible Hex source lock"
          )
      end
    end

    status =
      if scm == Mix.SCM.Git and
           (File.regular?(Path.join([opts[:dest], "..", "nix-support", "git-info"])) or
              not Mix.SCM.Git.checked_out?(source_opts)) do
        git_lock_status(source_opts)
      else
        scm.lock_status(source_opts)
      end

    if status != :ok do
      Mix.raise(
        "Nix precompiled dependency #{opts[:nix_app]} does not match its source lock (#{status})"
      )
    end
  end

  defp resolve_lock(opts) do
    lockfile = Mix.Project.config()[:lockfile]

    if is_nil(opts[:lock]) and System.get_env("MIX_NIX_LOCKLESS") == "1" and
         not File.exists?(lockfile) do
      lock =
        case opts[:nix_scm] do
          Hex.SCM ->
            binary = File.read!(Path.join(opts[:dest], ".hex"))
            {:ok, manifest} = apply(Hex.SCM, :parse_manifest, [binary])

            {:hex, manifest.name, manifest.version, manifest.inner_checksum, manifest.managers,
             nil, manifest.repo, manifest.outer_checksum}

          Mix.SCM.Git ->
            metadata = Path.join([opts[:dest], "..", "nix-support", "git-info"])
            [url, revision] = metadata |> File.read!() |> String.trim() |> String.split("\t")
            lock_opts = Keyword.take(opts, [:branch, :ref, :tag, :sparse, :subdir, :depth])
            lock_opts = if opts[:submodules], do: lock_opts ++ [submodules: true], else: lock_opts
            {:git, url, revision, lock_opts}

          Mix.SCM.Path ->
            nil
        end

      Keyword.put(opts, :lock, lock)
    else
      opts
    end
  end

  defp git_lock_status(opts) do
    metadata = Path.join([opts[:dest], "..", "nix-support", "git-info"])

    with {:ok, info} <- File.read(metadata),
         [url, revision] <- String.split(String.trim(info), "\t"),
         {:git, ^url, ^revision, lock_opts} <- opts[:lock],
         true <- String.match?(revision, ~r/\A[0-9a-f]{40}\z/),
         true <- Mix.SCM.Git.equal?(opts, Keyword.merge([git: url], lock_opts)),
         true <- git_fetch_options_match?(opts) do
      :ok
    else
      _ -> :mismatch
    end
  end

  defp git_fetch_options_match?(opts) do
    metadata = Path.join([opts[:dest], "..", "nix-support", "git-fetch-options"])

    case File.read(metadata) do
      {:ok, info} ->
        values =
          info
          |> String.split("\n", trim: true)
          |> Enum.map(fn line ->
            [key, value] = String.split(line, "\t", parts: 2)
            {key, value}
          end)

        requested_root = Enum.join(Enum.filter([opts[:sparse], opts[:subdir]], & &1), "/")
        root = List.keyfind(values, "rootDir", 0)

        (!opts[:submodules] or {"submodules", "true"} in values) and
          root == {"rootDir", requested_root}

      {:error, :enoent} ->
        !opts[:submodules] and !opts[:sparse] and !opts[:subdir]
    end
  end

  defp validate_toolchain!(opts) do
    artifact = opts[:nix_artifact]
    current = {System.version(), :erlang.system_info(:otp_release)}
    manifest = Path.join([artifact, ".mix", "compile.elixir_scm"])

    case File.read(manifest) do
      {:ok, binary} ->
        case :erlang.binary_to_term(binary) do
          {1, ^current, _scm} ->
            :ok

          _ ->
            Mix.raise(
              "Nix precompiled dependency #{opts[:nix_app]} has an incompatible toolchain"
            )
        end

      {:error, :enoent} ->
        metadata = Path.join([opts[:dest], "..", "nix-support", "beam-toolchain"])
        toolchain = metadata |> File.read!() |> String.split("\n", trim: true)
        otp = "otp\t#{:erlang.system_info(:otp_release)}"

        if otp not in toolchain or Enum.any?(toolchain, &String.starts_with?(&1, "elixir\t")) do
          Mix.raise(
            "Nix precompiled dependency #{opts[:nix_app]} has an incompatible or missing toolchain manifest"
          )
        end
    end
  end

  defp prepare_build!(opts) do
    build = opts[:build]
    artifact = opts[:nix_artifact]

    case File.lstat(build) do
      {:ok, %File.Stat{type: :symlink}} -> File.rm!(build)
      {:ok, %File.Stat{type: :directory}} -> :ok
      {:error, :enoent} -> :ok
    end

    File.mkdir_p!(build)

    for entry <- File.ls!(artifact), entry != ".mix" do
      destination = Path.join(build, entry)
      target = Path.join(artifact, entry)

      case File.read_link(destination) do
        {:ok, ^target} -> :ok
        {:error, :enoent} -> File.ln_s!(target, destination)
        _ -> Mix.raise("Nix precompiled build path is already occupied: #{destination}")
      end
    end

    manifest_dir = Path.join(build, ".mix")

    if match?({:ok, %File.Stat{type: :symlink}}, File.lstat(manifest_dir)) do
      Mix.raise("Nix precompiled manifest path must be writable: #{manifest_dir}")
    end

    File.mkdir_p!(manifest_dir)
    manifest = {1, {System.version(), :erlang.system_info(:otp_release)}, __MODULE__}
    File.write!(Path.join(manifest_dir, "compile.elixir_scm"), :erlang.term_to_binary(manifest))
  end

  defp reject_force!(opts) do
    if "deps.compile" in System.argv() and "--force" in System.argv() do
      Mix.raise("Cannot force compilation of Nix precompiled dependency #{opts[:nix_app]}")
    end
  end

  @impl Mix.SCM
  def format(opts), do: "Nix precompiled #{opts[:nix_scm].format(opts)}"

  @impl Mix.SCM
  def format_lock(opts), do: opts[:nix_scm].format_lock(opts)

  @impl Mix.SCM
  def equal?(left, right) do
    left[:nix_scm] == right[:nix_scm] and
      left[:nix_artifact] == right[:nix_artifact] and
      left[:nix_scm].equal?(left[:nix_original], right[:nix_original])
  end

  @impl Mix.SCM
  def managers(opts), do: opts[:nix_scm].managers(opts)

  @impl Mix.SCM
  def checkout(opts), do: Mix.raise("Cannot fetch Nix precompiled dependency #{opts[:nix_app]}")

  @impl Mix.SCM
  def update(opts), do: Mix.raise("Cannot update Nix precompiled dependency #{opts[:nix_app]}")
end

Mix.start()
Mix.SCM.prepend(Nix.SCM)
Mix.CLI.main(System.argv())
