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
  version = "0.6.0";
  patchLinkDirectory = ''
    substituteInPlace packages/chatto-client/package.json \
      --replace-fail '"linkDirectory": false' '"linkDirectory": true'
  '';

  src = fetchFromGitHub {
    owner = "chattocorp";
    repo = "chatto";
    tag = "v${version}";
    hash = "sha256-2k7OXZqJk1Jdfygdjc1sRnFVyu42a8lzaTOoddyHVbo=";
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
      hash = "sha256-he0siYF6hotoc+/6t5QFNkMG189Ks5nd9Hxncag3qDY=";
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

  vendorHash = "sha256-6x1BqDtJ0TxA3urr5wpyOPB9xSeAU/y5O0/V3V/61a8=";

  env = {
    CGO_ENABLED = 0;
    GOWORK = "off";
  };

  postPatch = ''
    substituteInPlace cli/go.mod \
      --replace-fail 'github.com/hashicorp/golang-lru/v2 v2.0.7 // indirect' \
      $'github.com/hashicorp/golang-lru/v2 v2.0.7 // indirect\n\tgithub.com/kylelemons/godebug v1.1.0 // indirect'

    install -D -m644 LICENSES/AGPL-3.0-or-later.txt cli/cmd/embedded/LICENSE
    install -D -m644 NOTICE cli/cmd/embedded/NOTICE

    rm -rf cli/internal/http_server/.client
    cp -r ${web} cli/internal/http_server/.client
  '';

  preCheck = ''
    export GOFLAGS="$GOFLAGS -tags=test_endpoints"
  '';

  checkFlags =
    let
      skippedTests = [
        "TestPrepareOperatorAPISocket/rejects_parent_directory_with_setgid_bit" # tries to setgid
        "TestAuthGenerationWindowRejectsAppliedRevocation/account_deletion" # races asynchronous credential cleanup
      ];
    in
    [ "-skip=^${builtins.concatStringsSep "$|^" skippedTests}$" ];

  postInstall = ''
    mv "$out/bin/cli" "$out/bin/chatto"
  '';

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
