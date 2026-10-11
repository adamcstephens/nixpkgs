{
  apprise,
  beamPackages,
  esbuild,
  fetchFromGitHub,
  fetchYarnDeps,
  fixup-yarn-lock,
  gnused,
  lib,
  nix-update-script,
  nodejs,
  sqlite,
  tailwindcss_4,
  yarn,
  yt-dlp,
}:
beamPackages.mixRelease rec {
  pname = "pinchflat-ngx";
  version = "2026.9.28";

  src = fetchFromGitHub {
    owner = "TheBadFella";
    repo = "Pinchflat-NGX";
    rev = version;
    hash = "sha256-zgw1SXVjypBnWhRwFfBSusF2YbQcDv3tMQxfeu5esSk=";

  };

  # force compile exqlite using our version
  env = {
    EXQLITE_USE_SYSTEM = "1";
    EXQLITE_SYSTEM_CFLAGS = "-I${sqlite.dev}/include";
    EXQLITE_SYSTEM_LDFLAGS = "-L${sqlite.out}/lib -lsqlite3";
  };

  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "mix-deps-${pname}";
    inherit src version;
    hash = "sha256-d17sRyIFkHRhzwofqvIicYb7uh4govbndV7owBLnLnU=";
  };
  removeCookie = false;

  yarnOfflineCache = fetchYarnDeps {
    yarnLock = "${src}/assets/yarn.lock";
    sha256 = "sha256-G1y07SHtLHbwvP/Gds8ew799t1+FpO4+yBJ+Xin72co=";
  };

  nativeBuildInputs = [
    gnused
    fixup-yarn-lock
    yarn
  ];
  buildInputs = [ nodejs ];

  postPatch = ''
    sed -i '/config :esbuild/a  path: "${lib.getExe esbuild}",' config/config.exs
    sed -i '/config :tailwind/a  path: "${lib.getExe tailwindcss_4}",' config/config.exs
  '';

  postBuild = ''
    export HOME=$PWD
    fixup-yarn-lock ~/assets/yarn.lock
    yarn --cwd assets config --offline set yarn-offline-mirror $yarnOfflineCache
    yarn --cwd assets install --offline --frozen-lockfile --ignore-engines --ignore-scripts --no-progress
    patchShebangs ~/assets/node_modules

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

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Enhanced, self-hosted YouTube media manager built on Pinchflat with Material 3 AMOLED UI, PostgreSQL support, OIDC SSO, and disk staging";
    homepage = "https://github.com/TheBadFella/Pinchflat-NGX";
    changelog = "https://github.com/TheBadFella/Pinchflat-NGX/releases/tag/v${version}";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ adamcstephens ];
    platforms = beamPackages.erlang.meta.platforms;
    mainProgram = "pinchflat";
  };
}
