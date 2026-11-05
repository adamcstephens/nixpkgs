{
  beamPackages,
  git,
  lib,
  runCommand,
  stdenv,
  writeText,
}:
let
  inherit (beamPackages)
    buildMix
    elixir
    hex
    mixBuildDirHook
    mixNixDepsSetupHook
    mixRelease
    ;

  fixtureSource =
    app: module: isGit:
    runCommand "${app}-source" { nativeBuildInputs = lib.optional isGit git; } ''
      cp --recursive ${./fixtures/dependency} "$out"
      chmod --recursive u+w "$out"
      substituteInPlace "$out/mix.exs" \
        --replace-fail 'dependency_fixture' '${app}' \
        --replace-fail 'DependencyFixture' '${module}'
      substituteInPlace "$out/lib/fixture.ex" \
        --replace-fail 'dependency_fixture' '${app}' \
        --replace-fail 'DependencyFixture' '${module}'
      ${lib.optionalString isGit ''
        export GIT_AUTHOR_NAME=Fixture GIT_COMMITTER_NAME=Fixture
        export GIT_AUTHOR_EMAIL=fixture@example.invalid GIT_COMMITTER_EMAIL=fixture@example.invalid
        export GIT_AUTHOR_DATE=2000-01-01T00:00:00Z GIT_COMMITTER_DATE=2000-01-01T00:00:00Z
        git init --initial-branch=main "$out"
        git -C "$out" add .
        git -C "$out" commit --message fixture
        git -C "$out" remote add origin "file://$out"
      ''}
    '';

  pathSource = fixtureSource "path_fixture" "FixturePath" false;
  gitSource = fixtureSource "git_fixture" "FixtureGit" true;
  existingPackages = import ../../../by-name/mo/mobilizon/mix.nix {
    inherit lib beamPackages;
  };

  dependencies = {
    jason = existingPackages.jason;
    telemetry = existingPackages.telemetry;
    path_fixture = buildMix {
      name = "path_fixture";
      version = "1.0.0";
      src = pathSource;
      env.ALLOW_DEPENDENCY_COMPILATION = "1";
    };
    git_fixture = buildMix {
      name = "git_fixture";
      version = "1.0.0";
      src = gitSource;
      env.ALLOW_DEPENDENCY_COMPILATION = "1";
    };
  };

  rootSource = runCommand "mix-precompiled-root-source" { nativeBuildInputs = [ git ]; } ''
    cp --recursive ${./fixtures/root} "$out"
    chmod --recursive u+w "$out"
    substituteInPlace "$out/mix.exs" \
      --replace-fail '@git_url@' 'file://${gitSource}' \
      --replace-fail '@path_source@' '${pathSource}' \
      --replace-fail '@editable_source@' '${./fixtures/editable}'
    IFS=, read -r package version jason_checksum repository < ${dependencies.jason.src}/.hex || true
    IFS=, read -r package version telemetry_checksum repository < ${dependencies.telemetry.src}/.hex || true
    jason_outer=$(sha256sum ${dependencies.jason.src.src})
    jason_outer="''${jason_outer%% *}"
    telemetry_outer=$(sha256sum ${dependencies.telemetry.src.src})
    telemetry_outer="''${telemetry_outer%% *}"
    revision=$(git -c safe.directory=${gitSource} -C ${gitSource} rev-parse HEAD)
    cat > "$out/mix.lock" <<EOF
    %{
      jason: {:hex, :jason, "${dependencies.jason.version}", "$jason_checksum", [:mix], [], "hexpm", "$jason_outer"},
      telemetry: {:hex, :telemetry, "${dependencies.telemetry.version}", "$telemetry_checksum", [:rebar3], [], "hexpm", "$telemetry_outer"},
      git_fixture: {:git, "file://${gitSource}", "$revision", [branch: "main"]}
    }
    EOF
    mkdir --parents "$out/config"
    echo 'import Config' > "$out/config/config.exs"
  '';

  registry = import ../hooks/mix-nix-deps.nix { inherit lib writeText; } dependencies;
  artifacts = lib.mapAttrsToList (
    app: dependency: "${dependency}/lib/erlang/lib/${app}-${dependency.version}"
  ) dependencies;
  snapshotArtifacts = "find ${lib.escapeShellArgs artifacts} -type f -print0 | sort --zero-terminated | xargs --null sha256sum";
  assertDependencies = ''
    mix run --no-start -e 'RootFixture.assert_dependencies!()'
    mix subprocess_fixture
  '';
in
{
  buildRebar3 = dependencies.telemetry;

  buildMix = buildMix {
    name = "root_fixture";
    version = "1.0.0";
    src = rootSource;
    beamDeps = builtins.attrValues dependencies;
    postBuild = ''
      mix compile
      ${assertDependencies}
      test -f _build/prod/lib/root_fixture/ebin/Elixir.RootFixture.beam
    '';
  };

  umbrella = buildMix {
    name = "umbrella_fixture";
    version = "1.0.0";
    src = ./fixtures/umbrella;
    beamDeps = [ dependencies.path_fixture ];
    postBuild = ''
      mix run --no-start -e ':umbrella = UmbrellaPeer.value()'
      test -f _build/prod/lib/path_fixture/ebin/Elixir.UmbrellaChild.beam
      test ! -L _build/prod/lib/path_fixture/ebin
    '';
  };

  mixRelease = mixRelease {
    pname = "root-fixture-release";
    version = "1.0.0";
    src = rootSource;
    mixNixDeps = dependencies;
    postBuild = ''
      test -z "''${MIX_NIX_LOCKLESS-}"
      ${assertDependencies}
    '';
    postInstall = ''
      "$out/bin/root_fixture" eval 'RootFixture.assert_dependencies!()'
      test -f "$out/lib/jason-${dependencies.jason.version}/ebin/Elixir.Jason.beam"
      test -f "$out/lib/telemetry-${dependencies.telemetry.version}/ebin/telemetry.beam"
      test -f "$out/lib/git_fixture-1.0.0/ebin/Elixir.FixtureGit.beam"
      test -f "$out/lib/path_fixture-1.0.0/ebin/Elixir.FixturePath.beam"
    '';
  };

  bootstrap = stdenv.mkDerivation {
    name = "mix-precompiled-bootstrap-integration";
    src = rootSource;
    __structuredAttrs = true;
    strictDeps = true;
    nativeBuildInputs = [
      elixir
      hex
      git
      mixBuildDirHook
      mixNixDepsSetupHook
    ];
    env = {
      MIX_ENV = "prod";
      MIX_TARGET = "host";
      MIX_BUILD_PREFIX = "prod";
      MIX_NIX_DEPS = registry;
      mixNixElixir = "${elixir}/bin/elixir";
      HEX_OFFLINE = "1";
      HOME = "/tmp/mix-precompiled-integration-home";
      LANG = if stdenv.hostPlatform.isLinux then "C.UTF-8" else "C";
      LC_CTYPE = if stdenv.hostPlatform.isLinux then "C.UTF-8" else "UTF-8";
    };
    buildPhase = ''
      runHook preBuild
      mkdir --parents "$HOME"
      ${snapshotArtifacts} > artifacts.before

      mix deps > deps.log 2>&1 || { cat deps.log; exit 1; }
      cat deps.log
      grep --quiet jason deps.log
      grep --quiet telemetry deps.log
      grep --quiet git_fixture deps.log
      grep --quiet path_fixture deps.log
      mix deps.compile
      mix deps.compile jason telemetry git_fixture path_fixture
      mix compile
      ${assertDependencies}
      test -f _build/prod/lib/root_fixture/ebin/Elixir.RootFixture.beam
      test -L _build/prod/lib/path_fixture/ebin
      test -d _build/prod/lib/path_fixture/.mix
      test ! -L _build/prod/lib/path_fixture/.mix
      test -L _build/prod/lib/telemetry/ebin
      test -f _build/prod/lib/editable_fixture/ebin/Elixir.FixtureEditable.beam
      test ! -L _build/prod/lib/editable_fixture/ebin

      expect_rejection() {
        local label="$1" pattern="$2"
        shift 2
        if "$@" > "$label.log" 2>&1; then
          cat "$label.log"
          echo "Expected rejection: $label" >&2
          exit 1
        fi
        cat "$label.log"
        grep --extended-regexp --ignore-case --quiet "$pattern" "$label.log"
        if grep --extended-regexp --ignore-case --quiet 'dependency recompilation is forbidden|permission denied|read-only file system' "$label.log"; then
          echo "Rejected through compilation or attempted immutable mutation: $label" >&2
          exit 1
        fi
      }

      replace_registry_field() {
        ${elixir}/bin/elixir -e '
          [registry, app, field, value] = System.argv()
          changed =
            registry
            |> File.read!()
            |> String.split("\n", trim: true)
            |> Enum.map(fn line ->
              fields = String.split(line, "\t")
              fields = if hd(fields) == app, do: List.replace_at(fields, String.to_integer(field), value), else: fields
              Enum.join(fields, "\t")
            end)
            |> Enum.join("\n")
          File.write!("altered-registry.tsv", changed <> "\n")
        ' ${registry} "$1" "$2" "$3"
        export MIX_NIX_DEPS="$PWD/altered-registry.tsv"
      }

      test -z "''${MIX_NIX_LOCKLESS-}"
      mv mix.lock mix.lock.saved
      expect_rejection missing-lock 'lock' mix compile
      env MIX_NIX_LOCKLESS=1 mix compile
      test ! -e mix.lock
      printf '%%{}\n' > mix.lock
      expect_rejection empty-lock 'lock' env MIX_NIX_LOCKLESS=1 mix compile
      ${elixir}/bin/elixir -e '
        {lock, _} = Code.eval_file("mix.lock.saved")
        File.write!("mix.lock", inspect(Map.delete(lock, :jason), limit: :infinity))
      '
      expect_rejection incomplete-lock 'lock' env MIX_NIX_LOCKLESS=1 mix compile
      mv mix.lock.saved mix.lock

      expect_rejection force 'precompiled|Nix|immutable' mix deps.compile --force
      expect_rejection named-force 'precompiled|Nix|immutable' mix deps.compile path_fixture --force
      test -f _build/prod/lib/path_fixture/ebin/Elixir.FixturePath.beam

      cp mix.exs mix.exs.original
      substituteInPlace mix.exs --replace-fail '~> 1.4' '~> 9.0'
      expect_rejection version 'version|requirement' mix compile
      cp mix.exs.original mix.exs

      cp mix.lock mix.lock.original
      ${elixir}/bin/elixir -e '
        {lock, _} = Code.eval_file("mix.lock")
        changed = Map.update!(lock, :jason, &put_elem(&1, 3, String.duplicate("0", 64)))
        File.write!("mix.lock", inspect(changed, limit: :infinity))
      '
      expect_rejection lock 'lock|checksum' mix compile
      expect_rejection compile-lock 'lock|checksum' mix deps.compile jason
      cp mix.lock.original mix.lock

      ${elixir}/bin/elixir -e '
        {lock, _} = Code.eval_file("mix.lock")
        changed = Map.update!(lock, :git_fixture, &put_elem(&1, 2, String.duplicate("0", 40)))
        File.write!("mix.lock", inspect(changed, limit: :infinity))
      '
      expect_rejection git-lock 'lock|revision|Git' mix compile
      expect_rejection compile-git-lock 'lock|revision|Git' mix deps.compile git_fixture
      cp mix.lock.original mix.lock

      echo 'import Config; config :path_fixture, :value, :different' > config/config.exs
      expect_rejection config 'compile|configuration|config' mix compile
      expect_rejection compile-config 'compile|configuration|config' mix deps.compile path_fixture
      echo 'import Config' > config/config.exs

      cp --recursive ${dependencies.path_fixture}/lib/erlang/lib/path_fixture-1.0.0 altered-artifact
      chmod --recursive u+w altered-artifact
      ${elixir}/bin/elixir -e '
        path = "altered-artifact/.mix/compile.elixir_scm"
        {1, {_elixir, otp}, scm} = path |> File.read!() |> :erlang.binary_to_term()
        File.write!(path, :erlang.term_to_binary({1, {"0.0.0", otp}, scm}))
      '
      replace_registry_field path_fixture 2 "$PWD/altered-artifact"
      expect_rejection toolchain 'toolchain|Elixir|version' mix compile
      expect_rejection compile-toolchain 'toolchain|Elixir|version' mix deps.compile path_fixture
      rm altered-artifact/ebin/path_fixture.app
      expect_rejection missing-app 'application|app file' mix compile
      expect_rejection compile-missing-app 'application|app file' mix deps.compile path_fixture
      export MIX_NIX_DEPS=${registry}

      mkdir --parents stripped-git
      cp --recursive ${dependencies.git_fixture}/{src,nix-support} stripped-git/
      chmod --recursive u+w stripped-git
      rm --recursive --force stripped-git/src/.git
      replace_registry_field git_fixture 1 "$PWD/stripped-git/src"
      mix compile
      mix deps.compile git_fixture
      rm stripped-git/nix-support/git-info
      expect_rejection missing-git-provenance 'lock|provenance' mix compile
      export MIX_NIX_DEPS=${registry}

      mkdir --parents altered-rebar
      cp --recursive ${dependencies.telemetry}/{src,nix-support} altered-rebar/
      chmod --recursive u+w altered-rebar
      printf 'otp\t0\n' > altered-rebar/nix-support/beam-toolchain
      replace_registry_field telemetry 1 "$PWD/altered-rebar/src"
      expect_rejection otp-toolchain 'toolchain|OTP' mix compile
      expect_rejection compile-otp-toolchain 'toolchain|OTP' mix deps.compile telemetry
      export MIX_NIX_DEPS=${registry}

      ${snapshotArtifacts} > artifacts.after
      cmp artifacts.before artifacts.after
      mix compile
      ${assertDependencies}
      runHook postBuild
    '';
    installPhase = ''
      mkdir --parents "$out"
      cp *.log artifacts.before artifacts.after "$out/"
    '';
  };
}
