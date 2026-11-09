{
  aws-lc,
  bzip2,
  fetchFromGitHub,
  lib,
  nix-update-script,
  openssl,
  pkg-config,
  rustPlatform,
  zlib,
  zstd,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "fakecloud";
  version = "0.51.0";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "faiscadev";
    repo = "fakecloud";
    tag = "v${finalAttrs.version}";
    hash = "sha256-zy7tNERZxAG53CvFl+GyQbAE0gBYzCbSo82+eu2IbwY=";
  };

  cargoHash = "sha256-MyPLxk4FRXSaVfJlfd6PItIckTa5i8ERr2oB29Ohog4=";

  nativeBuildInputs = [
    pkg-config
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    aws-lc
    bzip2
    openssl
    zlib
    zstd
  ];

  env = {
    OPENSSL_NO_VENDOR = true;
    ZSTD_SYS_USE_PKG_CONFIG = true;
  };

  cargoBuildFlags = [ "--bin=fakecloud" ];

  doCheck = false;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Free, open-source AWS emulator. LocalStack alternative: 107 services, 7,657 operations, true 100% Smithy conformance (258,545/258,545 variants pass). No account, no auth token, no paid tier";
    homepage = "https://github.com/faiscadev/fakecloud";
    changelog = "https://github.com/faiscadev/fakecloud/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ adamcstephens ];
    mainProgram = "fakecloud";
  };
})
