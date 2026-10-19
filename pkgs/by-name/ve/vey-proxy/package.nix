{
  lib,
  rustPlatform,
  fetchFromGitHub,
  c-ares,
  capnproto,
  pkg-config,
  openssl,
  python3,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "vey-proxy";
  version = "1.15.1";

  src = fetchFromGitHub {
    owner = "VEY-OSS";
    repo = "vey";
    tag = "vey-proxy-v${finalAttrs.version}";
    hash = "sha256-Ah9dGk80c7SQYe5zf1sak+Kw/gyswuyxxEsZCr99gw8=";
  };

  cargoHash = "sha256-1g33QRzbCkytH62/xImR12DvsX+PiySpRIcK4IG/dHI=";

  cargoBuildFlags = [
    "-p"
    "vey-proxy"
  ];
  cargoTestFlags = [
    "-p"
    "vey-proxy"
  ];

  nativeBuildInputs = [
    capnproto
    pkg-config
    python3
  ];

  buildInputs = [
    c-ares
    openssl
  ];

  meta = {
    description = "Feature-rich general-purpose proxy daemon";
    homepage = "https://github.com/VEY-OSS/vey";
    changelog = "https://github.com/VEY-OSS/vey/releases/tag/vey-proxy-v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "vey-proxy";
    platforms = lib.platforms.linux;
  };
})
