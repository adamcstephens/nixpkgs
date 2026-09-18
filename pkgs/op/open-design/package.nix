{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  nodejs_24,
  electron-bin,
  python3,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  nix-update-script,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "open-design";
  version = "0.22.2";

  src = fetchFromGitHub {
    owner = "nexu-io";
    repo = "open-design";
    tag = "open-design-v${finalAttrs.version}";
    hash = "sha256-ByqzuKVcNJNiL0tNg9TZafyAc2kF3b15toqNLlQY7IY=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 4;
    hash = "sha256-QGCkuSIRyI9Anlxi6toAgwfxuICqn14duOzMFFT5Lj8=";
  };

  nativeBuildInputs = [
    nodejs_24
    pnpm_10
    pnpmConfigHook
    python3
    makeWrapper
    copyDesktopItems
  ];

  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    NEXT_TELEMETRY_DISABLED = "1";
    OD_WEB_OUTPUT_MODE = "server";
    npm_config_nodedir = "${nodejs_24}";
    npm_execpath = "${pnpm_10}/bin/pnpm";
    npm_config_build_from_source = "true";
  };

  buildPhase = ''
    runHook preBuild

    pnpm --filter '@open-design/dsh-runtime...' --workspace-concurrency=1 --if-present run build
    pnpm --filter '@open-design/packaged^...' --workspace-concurrency=1 --if-present run build
    pnpm --filter @open-design/web run build:sidecar
    pnpm --filter @open-design/packaged run build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    appRoot="$out/lib/open-design/resources/app"
    mkdir --parents "$appRoot"

    export resourceRoot="$out/lib/open-design/resources/open-design"
    pnpm exec tsx --eval '
      import { copyBundledResourceTrees, packBundledDshRuntime } from "./tools/pack/src/resources/index.ts";
      async function main() {
        const options = { workspaceRoot: process.cwd(), resourceRoot: process.env.resourceRoot };
        await copyBundledResourceTrees(options);
        await packBundledDshRuntime(options);
      }
      main();
    '
    mkdir --parents "$resourceRoot/bin"
    cp ${lib.getExe nodejs_24} "$resourceRoot/bin/node"
    gzip --decompress --stdout apps/desktop/vendor/dom-to-pptx/dom-to-pptx.bundle.js.gz \
      > "$out/lib/open-design/resources/dom-to-pptx.bundle.js"

    workspaceRoot="$PWD"
    workspacePackages=$(pnpm --filter '@open-design/packaged...' list --depth=-1 --parseable)
    for package in $workspacePackages; do
      destination="$appRoot/''${package#"$workspaceRoot/"}"
      mkdir --parents "$destination"
      pnpm --dir "$package" pack --out "$TMPDIR/workspace-package.tgz"
      tar --extract --file "$TMPDIR/workspace-package.tgz" \
        --strip-components=1 --directory "$destination"
    done

    rm --recursive --force node_modules apps/*/node_modules packages/*/node_modules \
      tools/*/node_modules shells/*/node_modules e2e/node_modules
    pnpm install --offline --prod --filter-prod '@open-design/packaged...' \
      --frozen-lockfile --ignore-scripts
    pnpm --recursive rebuild better-sqlite3
    node ${nodejs_24}/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js \
      rebuild --directory=apps/daemon/node_modules/node-pty

    mv node_modules "$appRoot/"
    for package in $workspacePackages; do
      if [ -d "$package/node_modules" ]; then
        mv "$package/node_modules" "$appRoot/''${package#"$workspaceRoot/"}/"
      fi
    done
    cat > "$appRoot/package.json" <<EOF
    {"name":"open-design","version":"${finalAttrs.version}","main":"apps/packaged/dist/index.mjs","type":"module"}
    EOF

    cp apps/desktop/dist/main/preload.cjs "$out/lib/open-design/resources/app/preload.cjs"
    cat > "$out/lib/open-design/resources/open-design-config.json" <<EOF
    {"appVersion":"${finalAttrs.version}","namespace":"default","nodeCommandRelative":"open-design/bin/node"}
    EOF

    for file in ${electron-bin.dist}/*; do
      if [ "$(basename "$file")" != resources ] && [ "$(basename "$file")" != electron ]; then
        ln --symbolic "$file" "$out/lib/open-design/"
      fi
    done
    cp ${electron-bin.dist}/electron "$out/lib/open-design/open-design"
    makeWrapper "$out/lib/open-design/open-design" "$out/bin/open-design" \
      --unset ELECTRON_RUN_AS_NODE

    install --directory "$out/share/icons/hicolor/512x512/apps"
    install --mode=644 tools/pack/resources/linux/icon.png \
      "$out/share/icons/hicolor/512x512/apps/open-design.png"

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "open-design";
      desktopName = "Open Design";
      comment = finalAttrs.meta.description;
      exec = "open-design %U";
      icon = "open-design";
      categories = [ "Development" ];
      mimeTypes = [
        "x-scheme-handler/od"
        "x-scheme-handler/opendesign"
      ];
      startupWMClass = "Open Design";
    })
  ];

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version-regex=open-design-v(.*)" ];
  };

  meta = {
    description = "Local-first, agent-powered design workspace";
    homepage = "https://github.com/nexu-io/open-design";
    changelog = "https://github.com/nexu-io/open-design/releases/tag/open-design-v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "open-design";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    maintainers = [ ];
  };
})
