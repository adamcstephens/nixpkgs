{
  lib,
  fetchPnpmDeps,
  electron_42,
  makeDesktopItem,
  ffmpeg-headless,
  poppler-utils,
  git,
  bash,
  copyDesktopItems,
  server,
  nodejs,
  pnpm,
}:
let
  electron = electron_42;
in
server.overrideAttrs (
  finalAttrs: previousAttrs: {
    pname = "open-design-desktop";

    postPatch = previousAttrs.postPatch + ''
      substituteInPlace apps/packaged/src/config.ts \
        --replace-fail 'join(process.resourcesPath, relativeNodeCommand)' 'resolve(process.resourcesPath, relativeNodeCommand)'
    '';

    pnpmWorkspaces = previousAttrs.pnpmWorkspaces ++ [ "@open-design/packaged..." ];
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
      hash = "sha256-eKlf5Q86UN4ZB8m3hUkCUYHSe1jJDTnCNTFDDXGE1dg=";
    };

    nativeBuildInputs = previousAttrs.nativeBuildInputs ++ [ copyDesktopItems ];
    env = previousAttrs.env // {
      OD_WEB_OUTPUT_MODE = "server";
      ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    };

    buildPhase = previousAttrs.buildPhase + ''
      pnpm --filter '@open-design/desktop...' --workspace-concurrency=1 --if-present run build
      pnpm --filter @open-design/web run build:sidecar
      pnpm --filter @open-design/packaged run build
    '';

    installPhase = ''
      runHook preInstall
      appRoot="$out/lib/open-design-desktop"
      pnpm --config.inject-workspace-packages=true --filter @open-design/packaged deploy \
        --prod --offline --frozen-lockfile --ignore-scripts "$appRoot"
      rm --recursive "$appRoot/node_modules/@open-design/web/src"
      daemonRoot="$(realpath "$appRoot/node_modules/@open-design/daemon")"
      resourceRoot="$(realpath "$daemonRoot/../..")/open-design"
      cp apps/desktop/dist/main/preload.cjs "$appRoot/"
      cp --recursive apps/desktop/vendor "$appRoot/node_modules/@open-design/desktop/"
      for module in better-sqlite3 node-pty; do
        moduleRoot="$(dirname "$(node --eval \
          'console.log(require.resolve(process.argv[1] + "/package.json", { paths: [process.argv[2]] }))' \
          "$module" "$daemonRoot")")"
        mkdir --parents "$moduleRoot/build/Release"
        cp apps/daemon/node_modules/"$module"/build/Release/*.node "$moduleRoot/build/Release/"
      done
      find "$appRoot/node_modules" -type f -name ffmpeg \
        -exec ln --symbolic --force ${lib.getExe ffmpeg-headless} {} \;
      find "$appRoot/node_modules" -type f -name ffprobe \
        -exec ln --symbolic --force ${lib.getExe' ffmpeg-headless "ffprobe"} {} \;
      export OD_DESKTOP_RESOURCE_ROOT="$resourceRoot"
      npm_execpath=${lib.getExe pnpm} node --experimental-strip-types --input-type=module --eval '
        import { copyBundledResourceTrees, packBundledDshRuntime } from "./tools/pack/src/resources/index.ts";
        const resourceRoot = process.env.OD_DESKTOP_RESOURCE_ROOT;
        await copyBundledResourceTrees({ workspaceRoot: process.cwd(), resourceRoot });
        await packBundledDshRuntime({ workspaceRoot: process.cwd(), resourceRoot });
      '
      jq --null-input --arg version '${finalAttrs.version}' \
        --arg resources "$resourceRoot" --arg node '${lib.getExe nodejs}' \
        '{ appVersion: $version, namespace: "nixpkgs", resourceRoot: $resources, nodeCommandRelative: $node, webOutputMode: "server" }' \
        > "$appRoot/open-design-config.json"
      makeWrapper ${lib.getExe electron} "$out/bin/open-design-desktop" \
        --add-flags "$appRoot" \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
        --unset ELECTRON_RUN_AS_NODE \
        --set NODE_ENV production \
        --set OD_PACKAGED_CONFIG_PATH "$appRoot/open-design-config.json" \
        --set OD_UPDATE_ENABLED 0 \
        --prefix PATH : ${
          lib.makeBinPath [
            ffmpeg-headless
            poppler-utils
            git
            bash
          ]
        }
      mkdir --parents "$out/share/icons/hicolor/1024x1024/apps"
      install --mode=444 tools/pack/resources/linux/icon.png \
        "$out/share/icons/hicolor/1024x1024/apps/open-design-desktop.png"
      runHook postInstall
    '';

    desktopItems = [
      (makeDesktopItem {
        name = "open-design-desktop";
        desktopName = "OpenDesign";
        exec = "open-design-desktop %U";
        icon = "open-design-desktop";
        categories = [ "Graphics" ];
        mimeTypes = [ "x-scheme-handler/opendesign" ];
      })
    ];

    passthru = { };
    meta = previousAttrs.meta // {
      description = "Local-first design agent workspace desktop application";
      mainProgram = "open-design-desktop";
    };
  }
)
