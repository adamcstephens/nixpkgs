{
  buildGoModule,
  fetchFromGitHub,
  fetchPnpmDeps,
  lib,
  nix-update-script,
  nodejs,
  pnpmConfigHook,
  pnpm_10,
  stdenvNoCC,
  writableTmpDirAsHomeHook,
}:
let
  pname = "chatto";
  version = "0.4.18";

  src = fetchFromGitHub {
    owner = "chattocorp";
    repo = "chatto";
    tag = "v${version}";
    hash = "sha256-ew+p2C5EtQGWcgKc15eBCJGbLL8kJyYJ4jjEPIS9QUg=";
  };

  web = stdenvNoCC.mkDerivation (webFinalAttrs: {
    pname = "${pname}-web";
    inherit src version;

    pnpmDeps = fetchPnpmDeps {
      inherit (webFinalAttrs) pname version src;
      pnpm = pnpm_10;
      fetcherVersion = 4;
      hash = "sha256-kZUWWThAitZ3kgFGfuoigiiMoEsUsQF6Uu1BaVfoLDA=";
    };

    nativeBuildInputs = [
      nodejs
      pnpm_10
      pnpmConfigHook
      writableTmpDirAsHomeHook
    ];

    buildPhase = ''
      runHook preBuild

      pnpm --filter @chatto/api-types build
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

  vendorHash = "sha256-Fif+HL2HVGdy1gdTFWVP5aEvkRtoACW1PtH8RxidddQ=";

  env.CGO_ENABLED = 0;

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
