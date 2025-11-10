{
  lib,
  fetchFromGitHub,
  fetchYarnDeps,
  beamPackages,
  writeShellScript,
  yarn,
  nodejs,
  esbuild,
  tailwindcss,
  fixup-yarn-lock,
  apprise,
  mix2nix,
  nixfmt,
  nix-update,
  yt-dlp,
}:
beamPackages.mixRelease rec {
  pname = "pinchflat";
  version = "2025.9.26";
  src = fetchFromGitHub {
    owner = "kieraneglin";
    repo = "pinchflat";
    rev = "v${version}";
    hash = "sha256-45lw/48WTlfwTMWsCryNY3g3W9Ff31vMvw0W9znAJGk=";

  };

  mixNixDeps = import ./mix.nix {
    inherit beamPackages lib;
    overrides = _: super: {
      exqlite = super.exqlite.overrideAttrs (_: {
        preConfigure = ''
          export ELIXIR_MAKE_CACHE_DIR="$TMPDIR/.cache"
        '';
      });
    };
  };
  removeCookie = false;

  yarnOfflineCache = fetchYarnDeps {
    yarnLock = "${src}/assets/yarn.lock";
    sha256 = "sha256-xJL+qcohtu+OmZ31E1QU9uqBWAFGejKIO3XRd+R6z/4=";
  };

  nativeBuildInputs = [
    fixup-yarn-lock
    tailwindcss
    yarn
  ];
  buildInputs = [ nodejs ];

  postBuild = ''
    export HOME=$PWD
    fixup-yarn-lock ~/assets/yarn.lock
    yarn --cwd assets config --offline set yarn-offline-mirror $yarnOfflineCache
    yarn --cwd assets install --offline --frozen-lockfile --ignore-engines --ignore-scripts --no-progress
    patchShebangs ~/assets/node_modules

    # phoenixframework expects platform-specific tailwind/esbuild binaries in a specific location:
    # https://github.com/phoenixframework/tailwind/blob/194ab0f979782e4ccf2fe796042bf8e20967df93/lib/tailwind.ex#L243-L251
    targets="linux-x64 linux-arm64 macos-x64 macos-arm64"
    for target in $targets; do
      ln -s "${tailwindcss}/bin/tailwindcss" "_build/tailwind-$target"
      ln -s "${esbuild}/bin/esbuild" "_build/esbuild-$target"
    done

    mix do deps.loadpaths --no-deps-check, tailwind default --minify + esbuild default --minify + phx.digest
  '';

  postInstall = ''
    wrapProgram $out/bin/pinchflat --prefix PATH : ${
      lib.makeBinPath [
        apprise
        yt-dlp
      ]
    }
  '';

  passthru.updateScript = writeShellScript "update.sh" ''
    set -eou pipefail

    ${lib.getExe nix-update} pinchflat
    ${lib.getExe mix2nix} '${src}/mix.lock' > pkgs/by-name/pi/pinchflat/mix.nix
    ${lib.getExe nixfmt} pkgs/by-name/pi/pinchflat/mix.nix
  '';

  meta = {
    description = "Your next YouTube media manager";
    homepage = "https://github.com/kieraneglin/pinchflat";
    changelog = "https://github.com/kieraneglin/pinchflat/releases/tag/v${version}";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ charludo ];
    platforms = lib.platforms.unix;
    mainProgram = "pinchflat";
  };
}
