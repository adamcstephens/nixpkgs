{
  lib,
  stdenv,
  callPackage,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  nodejs_24,
  python3,
  jq,
  makeWrapper,
  autoPatchelfHook,
  nix-update-script,
  ffmpeg-headless,
  poppler-utils,
  git,
  bash,
}:
let
  nodejs = nodejs_24;
  pnpm = pnpm_10.override { inherit nodejs; };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "open-design";
  version = "0.24.1";

  src = fetchFromGitHub {
    owner = "nexu-io";
    repo = "open-design";
    tag = "open-design-v${finalAttrs.version}";
    hash = "sha256-CJpr0JIww5XGgPqTDwaQlPBCB0Kz5GtOCOyKMfT9zyA=";
  };

  postPatch = ''
    substituteInPlace package.json --replace-fail '>=10.33.2 <11' '>=10 <11'
  '';

  pnpmWorkspaces = [
    "@open-design/daemon..."
    "@open-design/web..."
    "@open-design/dsh-runtime..."
  ];
  pnpmInstallFlags = [ "--ignore-scripts" ];
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs)
      pname
      version
      src
      postPatch
      pnpmWorkspaces
      pnpmInstallFlags
      ;
    inherit pnpm;
    fetcherVersion = 3;
    hash = "sha256-HSxHPW2+EqbFg08iIVZ9omaGj+5qU1UPiVMjh2p0jCA=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm
    (pnpmConfigHook.override { inherit pnpm; })
    python3
    jq
    makeWrapper
    autoPatchelfHook
  ];
  buildInputs = [ stdenv.cc.cc.lib ];

  env = {
    npm_config_manage_package_manager_versions = "false";
    npm_config_nodedir = "${nodejs}";
    npm_config_build_from_source = "true";
    NEXT_TELEMETRY_DISABLED = "1";
    NODE_OPTIONS = "--max-old-space-size=4096";
  };

  buildPhase = ''
    runHook preBuild
    pnpm --recursive rebuild better-sqlite3 esbuild
    node ${nodejs}/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js \
      rebuild --directory=apps/daemon/node_modules/node-pty
    pnpm --filter '@open-design/daemon...' --workspace-concurrency=1 --if-present run build
    pnpm --filter '@open-design/dsh-runtime...' --workspace-concurrency=1 --if-present run build
    pnpm --filter '@open-design/web...' --workspace-concurrency=1 --if-present run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir --parents "$out/lib/open-design/apps/web" "$out/bin"
    pnpm --config.inject-workspace-packages=true --filter @open-design/daemon deploy --prod --offline --frozen-lockfile --ignore-scripts "$out/lib/open-design/apps/daemon"
    for module in better-sqlite3 node-pty; do
      mkdir --parents "$out/lib/open-design/apps/daemon/node_modules/$module/build/Release"
    done
    cp apps/daemon/node_modules/better-sqlite3/build/Release/better_sqlite3.node \
      "$out/lib/open-design/apps/daemon/node_modules/better-sqlite3/build/Release/"
    cp apps/daemon/node_modules/node-pty/build/Release/pty.node \
      "$out/lib/open-design/apps/daemon/node_modules/node-pty/build/Release/"
    cp --recursive apps/web/out "$out/lib/open-design/apps/web/"
    runtimeRoot="$out/lib/open-design/agent-runtimes/deepseek-harness"
    mkdir --parents "$runtimeRoot"
    pnpm --dir packages/dsh-runtime pack --pack-destination "$runtimeRoot"
    for tarball in "$runtimeRoot"/*.tgz; do
      jq --null-input \
        --arg file "''${tarball##*/}" \
        --arg version "$(jq --raw-output .version packages/dsh-runtime/package.json)" \
        --arg sha256 "$(sha256sum "$tarball" | cut --delimiter=' ' --fields=1)" \
        '{ file: $file, packageName: "@open-design/dsh-runtime", schemaVersion: 1, sha256: $sha256, version: $version }' \
        > "$runtimeRoot/manifest.json"
    done
    cp --recursive skills design-templates design-systems craft prompt-templates assets data plugins "$out/lib/open-design/"
    find "$out/lib/open-design/apps/daemon/node_modules" \
      -type f -name ffmpeg \
      -exec ln --symbolic --force ${lib.getExe ffmpeg-headless} {} \;
    find "$out/lib/open-design/apps/daemon/node_modules" \
      -type f -name ffprobe \
      -exec ln --symbolic --force ${lib.getExe' ffmpeg-headless "ffprobe"} {} \;
    makeWrapper ${lib.getExe nodejs} "$out/bin/open-design" \
      --add-flags "$out/lib/open-design/apps/daemon/dist/cli.js" \
      --add-flags "--no-open" \
      --run 'export OD_DATA_DIR="''${OD_DATA_DIR:-''${XDG_DATA_HOME:-$HOME/.local/share}/open-design}"' \
      --set NODE_ENV production \
      --set OD_APP_VERSION ${finalAttrs.version} \
      --prefix PATH : ${
        lib.makeBinPath [
          ffmpeg-headless
          poppler-utils
          git
          bash
        ]
      }
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version-regex=^open-design-v(.*)$" ];
  };
  passthru.desktop = callPackage ./desktop.nix {
    inherit (finalAttrs) src version meta;
    inherit nodejs pnpm;
  };

  meta = {
    description = "Local-first design agent workspace server";
    homepage = "https://github.com/nexu-io/open-design";
    license = lib.licenses.asl20;
    mainProgram = "open-design";
    platforms = lib.platforms.linux;
  };
})
