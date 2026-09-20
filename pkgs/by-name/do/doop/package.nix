{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  bun,
  nodejs_22,
  chromium,
  makeWrapper,
  writableTmpDirAsHomeHook,
  nix-update-script,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "doop";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "kgoedecke";
    repo = "doop";
    tag = "v${finalAttrs.version}";
    hash = "sha256-RH4+LC9uvEq+Q8pKkTugvQpXzMM6I65f/EhFvseTfaM=";
  };

  node_modules = stdenvNoCC.mkDerivation {
    pname = "${finalAttrs.pname}-node_modules";
    inherit (finalAttrs) version src;

    nativeBuildInputs = [
      bun
      writableTmpDirAsHomeHook
    ];
    impureEnvVars = lib.fetchers.proxyImpureEnvVars;
    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      export BUN_INSTALL_CACHE_DIR=$(mktemp --directory)
      bun install --cpu="*" --os="*" --frozen-lockfile --ignore-scripts --no-progress
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir --parents $out
      cp --recursive node_modules $out/
      runHook postInstall
    '';

    dontFixup = true;
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-mp1IV98zW8rLKyMHJ8KLV9UuLrqoA7wb7ChvmXm6hro=";
  };

  nativeBuildInputs = [
    nodejs_22
    makeWrapper
  ];

  postPatch = ''
    substituteInPlace server/index.ts \
      --replace-fail "path.join(process.cwd(), 'dist'" "path.join('$out/share/doop/dist'"
  '';

  configurePhase = ''
    runHook preConfigure
    cp --recursive ${finalAttrs.node_modules}/node_modules .
    chmod --recursive u+w node_modules
    patchShebangs node_modules
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    node node_modules/vite/bin/vite.js build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir --parents $out/share/doop
    cp --recursive package.json node_modules dist server shared $out/share/doop/
    makeWrapper ${lib.getExe nodejs_22} $out/bin/doop \
      --add-flags "$out/share/doop/node_modules/tsx/dist/cli.mjs $out/share/doop/server/index.ts" \
      --set NODE_ENV production \
      --set-default CHROME_PATH ${lib.getExe chromium}
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version-regex=^v([0-9.]+)$" ];
  };

  meta = {
    description = "Multiplayer design canvas with a built-in MCP server";
    longDescription = ''
      Runs the production web server and serves the bundled web frontend.
      Set BETTER_AUTH_SECRET and BETTER_AUTH_URL before starting doop.
      PORT defaults to 4400. Local database and uploaded assets are stored
      in data/ under the working directory. Set DATABASE_URL to use an
      external PostgreSQL database instead of embedded PGlite.
    '';
    homepage = "https://github.com/kgoedecke/doop";
    changelog = "https://github.com/kgoedecke/doop/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.agpl3Only;
    maintainers = [ ];
    mainProgram = "doop";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
