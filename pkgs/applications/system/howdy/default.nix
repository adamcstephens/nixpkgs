{ stdenv
, lib
, bzip2
, fetchFromGitHub
, fetchurl
, fmt
, gettext
, inih
, installShellFiles
, libevdev
, meson
, ninja
, pam
, pkg-config
, python3
}:

let
  data = let 
    baseurl = "https://github.com/davisking/dlib-models/raw/daf943f7819a3dda8aec4276754ef918dc26491f";
  in {
    "dlib_face_recognition_resnet_model_v1.dat" = fetchurl {
      url = "${baseurl}/dlib_face_recognition_resnet_model_v1.dat.bz2";
      sha256 = "0fjm265l1fz5zdzx5n5yphl0v0vfajyw50ffamc4cd74848gdcdb";
    };
    "mmod_human_face_detector.dat" = fetchurl {
      url = "${baseurl}/mmod_human_face_detector.dat.bz2";
      sha256 = "117wv582nsn585am2n9mg5q830qnn8skjr1yxgaiihcjy109x7nv";
    };
    "shape_predictor_5_face_landmarks.dat" = fetchurl {
      url = "${baseurl}/shape_predictor_5_face_landmarks.dat.bz2";
      sha256 = "0wm4bbwnja7ik7r28pv00qrl3i1h6811zkgnjfvzv7jwpyz7ny3f";
    };
  };

  py = python3.withPackages (p: [
    p.face_recognition
    (p.opencv4.override { enableGtk3 = true; })
  ]);
in
stdenv.mkDerivation {
  pname = "howdy";
  version = "unstable-2023-02-28";
  
  src = fetchFromGitHub {
    owner = "boltgolt";
    repo = "howdy";
    rev = "e881cc25935c7d39a074e9701a06b1fce96cc185";
    hash = "sha256-BHS1J0SUNbCeAnTXrOQCtBJTaSYa5jtYYtTgfycv7VM=";
  };

  patches = [
    # Change directory with configuration from `/etc` to `/var/lib`, since the service is expected to modify it.
    ./howdy.patch
  ];

  postPatch =
    let
      howdypath = "${placeholder "out"}/lib/security/howdy";
    in
    ''
      substituteInPlace howdy/src/cli/add.py --replace "@HOWDYPATH@" "${howdypath}"
      substituteInPlace howdy/src/cli/config.py --replace '/bin/nano' 'nano'
      substituteInPlace howdy/src/cli/test.py --replace "@HOWDYPATH@" "${howdypath}"

      substituteInPlace howdy/src/pam/main.cc \
        --replace "python3" "${py}/bin/python" \
        --replace "/lib/security/howdy/compare.py" "${howdypath}/compare.py"

      substituteInPlace howdy/src/compare.py \
        --replace "/lib/security/howdy" "${howdypath}" \
        --replace "@HOWDYPATH@" "${howdypath}"
    '';

  nativeBuildInputs = [
    bzip2
    installShellFiles
    meson
    ninja
    pkg-config
  ];

  buildInputs = [
    fmt
    gettext
    inih
    libevdev
    pam
    py
  ];

  # build howdy_pam
  preConfigure = ''
    cd howdy/src/pam

    # works around hardcoded install_dir: '/lib/security'.
    # See https://github.com/boltgolt/howdy/blob/30728a6d3634479c24ffd4e094c34a30bbb43058/howdy/src/pam/meson.build#L22
    export DESTDIR=$out
  '';

  postInstall =
    let
      libDir = "$out/lib/security/howdy";
      inherit (lib) mapAttrsToList concatStrings;
    in
    ''
      # done with howdy_pam, go back to source root
      cd ../../../..

      mkdir -p $out/share/licenses/howdy
      install -Dm644 LICENSE $out/share/licenses/howdy/LICENSE
      rm -rf howdy/src/pam
      mkdir -p ${libDir}
      cp -r howdy/src/* ${libDir}

      rm -rf ${libDir}/pam-config ${libDir}/dlib-data/*
      ${concatStrings (mapAttrsToList (n: v: ''
        bzip2 -dc ${v} > ${libDir}/dlib-data/${n}
      '') data)}

      mkdir -p $out/bin
      ln -s ${libDir}/cli.py $out/bin/howdy

      mkdir -p "$out/share/bash-completion/completions"
      installShellCompletion --bash howdy/src/autocomplete/howdy
    '';

  meta = {
    description = "Windows Hello™ style facial authentication for Linux";
    homepage = "https://github.com/boltgolt/howdy";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = with lib.maintainers; [ fufexan ];
  };
}
