{
  version,
  hash,
  cargoHash,
  eol ? false,
}:

{ lib
, stdenv
, rustPlatform
, fetchFromGitea
, fetchpatch
, openssl
, pkg-config
, protobuf
, cacert
, darwin
, garage
, nixosTests
}:

rustPlatform.buildRustPackage {
  pname = "garage";
  inherit version;

  src = fetchFromGitea {
    domain = "git.deuxfleurs.fr";
    owner = "Deuxfleurs";
    repo = "garage";
    rev = "v${version}";
    inherit hash;
  };

  inherit cargoHash;

  nativeBuildInputs = [ protobuf pkg-config ];

  buildInputs = [
    openssl
  ] ++ lib.optional stdenv.isDarwin darwin.apple_sdk.frameworks.Security;

  checkInputs = [
    cacert
  ];

  OPENSSL_NO_VENDOR = true;

  # See https://git.deuxfleurs.fr/Deuxfleurs/garage/src/tag/v0.8.2/nix/compile.nix#L192-L198
  # on version changes for checking if changes are required here
  buildFeatures = [
    "kubernetes-discovery"
    "bundled-libs"
    "sled"
    "metrics"
    "k2v"
    "telemetry-otlp"
    "lmdb"
    "sqlite"
    "consul-discovery"
  ];

  # To make integration tests pass, we include the optional k2v feature here,
  # but in buildFeatures only for version 0.8+, where it's enabled by default.
  # See: https://garagehq.deuxfleurs.fr/documentation/reference-manual/k2v/
  checkFeatures = [
    "k2v"
    "kubernetes-discovery"
    "bundled-libs"
    "sled"
    "lmdb"
    "sqlite"
  ];

  passthru.tests = nixosTests.garage;

  meta = {
    description = "S3-compatible object store for small self-hosted geo-distributed deployments";
    changelog = "https://git.deuxfleurs.fr/Deuxfleurs/garage/releases/tag/v${version}";
    homepage = "https://garagehq.deuxfleurs.fr";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ nickcao _0x4A6F teutat3s raitobezarius ];
    knownVulnerabilities = (lib.optional eol "Garage version ${version} is EOL");
    broken = stdenv.isDarwin && lib.versionOlder version "0.9";
    mainProgram = "garage";
  };
}
