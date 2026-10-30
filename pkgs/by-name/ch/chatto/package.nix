{
  buildGoModule,
  fetchFromGitHub,
  fetchPnpmDeps,
  lib,
  nix-update-script,
  nodejs,
  pnpmConfigHook,
  pnpm_11,
  stdenvNoCC,
  writableTmpDirAsHomeHook,
}:
let
  pname = "chatto";
  version = "0.5.0-beta.26";
  patchLinkDirectory = ''
    substituteInPlace packages/chatto-client/package.json \
      --replace-fail '"linkDirectory": false' '"linkDirectory": true'
  '';

  src = fetchFromGitHub {
    owner = "chattocorp";
    repo = "chatto";
    tag = "v${version}";
    hash = "sha256-AumYjH/ETuA/WxMWwPY7OQNyftv0MlbVB2te5cr60bA=";
  };

  web = stdenvNoCC.mkDerivation (webFinalAttrs: {
    pname = "${pname}-web";
    inherit src version;
    postPatch = patchLinkDirectory;

    pnpmDeps = fetchPnpmDeps {
      inherit (webFinalAttrs) pname version src;
      pnpm = pnpm_11;
      fetcherVersion = 4;
      postPatch = patchLinkDirectory;
      hash = "sha256-DhMucO1CvMp0WPBS3rM/70in2A67eq2xsM97wG9QY+k=";
    };

    nativeBuildInputs = [
      nodejs
      pnpm_11
      pnpmConfigHook
      writableTmpDirAsHomeHook
    ];

    buildPhase = ''
      runHook preBuild

      pnpm --filter @chatto/translatto build
      pnpm --filter chatto-frontend build

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      cp -r apps/frontend/build $out

      runHook postInstall
    '';
  });
in
buildGoModule (finalAttrs: {
  inherit pname version src;

  __structuredAttrs = true;
  strictDeps = true;

  modRoot = "cli";

  vendorHash = "sha256-why5SEGsr2Ne2r5iHOepMnPRWlqbt26FPKlMjhnf6t4=";

  env = {
    CGO_ENABLED = 0;
    GOWORK = "off";
  };

  postPatch = ''
    install -D -m644 LICENSES/AGPL-3.0-or-later.txt cli/cmd/embedded/LICENSE
    install -D -m644 NOTICE cli/cmd/embedded/NOTICE

    rm -rf cli/internal/http_server/.client
    cp -r ${web} cli/internal/http_server/.client
  '';

  checkFlags =
    let
      skippedTests = [
        "TestPrepareOperatorAPISocket/rejects_parent_directory_with_setgid_bit" # tries to setgid
      ];
    in
    [ "-skip=^${builtins.concatStringsSep "$|^" skippedTests}$" ];

  passthru = {
    inherit web;
    updateScript = nix-update-script {
      extraArgs = [
        "--subpackage"
        "web"
      ];
    };
  };

  meta = {
    description = "A really good chat application that you can self-host";
    homepage = "https://github.com/chattocorp/chatto";
    changelog = "https://github.com/chattocorp/chatto/blob/${finalAttrs.src.rev}/CHANGELOG.md";
    license = with lib.licenses; [
      agpl3Plus
      asl20
    ];
    maintainers = with lib.maintainers; [ ];
    mainProgram = "chatto";
    platforms = lib.platforms.all;
  };
})
