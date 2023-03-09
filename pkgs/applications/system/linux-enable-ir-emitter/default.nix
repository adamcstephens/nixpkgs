{ stdenv
, lib
, makeWrapper
, fetchFromGitHub
, fetchurl
, meson
, ninja
, pkg-config
, python3
, opencv
, usbutils
}:
stdenv.mkDerivation rec {
  pname = "linux-enable-ir-emitter";
  version = "4.5.0";

  src = fetchFromGitHub {
    owner = "EmixamPP";
    repo = pname;
    rev = version;
    hash = "sha256-Dv1ukn2TkXfBk1vc+6Uq7tw8WwCAfIcKl13BoOifz+Q=";
  };

  patches = [
    # Prevent `linux-enable-ir-emitter configure` from trying to enable systemd service, NixOS manages those declaratively.
    ./remove-boot-set.patch
  ];

  nativeBuildInputs = [
    makeWrapper
    meson
    ninja
    pkg-config
  ];
  buildInputs = [
    python3
    opencv
  ];

  postInstall = ''
    wrapProgram $out/bin/${pname} --prefix PATH : ${lib.makeBinPath [usbutils]}
  '';

  meta = {
    description = "Provides support for infrared cameras that are not directly enabled out-of-the box";
    homepage = "https://github.com/EmixamPP/linux-enable-ir-emitter";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ fufexan ];
    platforms = lib.platforms.linux;
  };
}
