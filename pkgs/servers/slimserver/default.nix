{ faad2
, fetchFromGitHub
, fetchurl
, flac
, lame
, lib
, makeWrapper
, monkeysAudio
, nixosTests
, perl536Packages
, sox
, stdenv
, wavpack
, zlib
, enableUnfreeFirmware ? false
}:

let
  perlPackages = perl536Packages;
in
perlPackages.buildPerlPackage rec {
  pname = "slimserver";
  version = "8.3.1";

  src = fetchFromGitHub {
    owner = "Logitech";
    repo = "slimserver";
    rev = version;
    hash = "sha256-yMFOwh/oPiJnUsKWBGvd/GZLjkWocMAUK0r+Hx/SUPo=";
  };

  nativeBuildInputs = [ makeWrapper ];

  # https://github.com/Logitech/slimserver-vendor/blob/public/8.3/CPAN/buildme.sh#L578
  buildInputs = [
    (perlPackages.AudioScan.overrideAttrs (_: {
      version = "1.06";
      src = fetchurl {
        url = "https://github.com/Logitech/slimserver-vendor/raw/947eb3a4efa1668ffde8f3fb5903ad462518c9a1/CPAN/Audio-Scan-1.06.tar.gz";
        hash = "sha256-soZhcdFABBlmY8qlxbbB7LFHHddO6LQlvA37OzACM+I=";
      };
    }))
    perlPackages.ClassC3
    perlPackages.ClassXSAccessor
    perlPackages.CompressRawZlib
    perlPackages.CryptOpenSSLRSA
    perlPackages.DBI
    perlPackages.DBDSQLite
    perlPackages.DigestSHA1
    perlPackages.EV
    perlPackages.EncodeDetect
    perlPackages.HTMLParser
    perlPackages.ImageScale
    perlPackages.IOAIO
    perlPackages.IOInterface
    perlPackages.IOSocketSSL
    perlPackages.JSONXS
    perlPackages.JSONXSVersionOneAndTwo
    perlPackages.MP3CutGapless
    perlPackages.SubName
    perlPackages.TemplateToolkit
    perlPackages.XMLParser
    perlPackages.YAMLLibYAML # YAML::XS
  ]
  ++ (lib.optional stdenv.isDarwin perlPackages.MacFSEvents)
  ++ (lib.optional stdenv.isLinux perlPackages.LinuxInotify2);

  prePatch = ''
    # remove vendored binaries and modules
    rm -rf Bin
    rm -rf CPAN/arch

    # remove modules which conflict with nixpkgs versions
    rm -rf CPAN/Class/XSAccessor* CPAN/DBD/SQLite* CPAN/Image/Scale* CPAN/XML/Parser*

    ${lib.optionalString (!enableUnfreeFirmware) ''
      # remove unfree firmware
      rm -rf Firmware
    ''}

    touch Makefile.PL
  '';

  doCheck = false;

  installPhase = ''
    cp -r . $out
    wrapProgram $out/slimserver.pl \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ zlib stdenv.cc.cc.lib ]}" \
      --prefix PATH : "${lib.makeBinPath ([ lame flac faad2 sox wavpack ] ++ (lib.optional stdenv.isLinux monkeysAudio))}"
    mkdir $out/bin
    ln -s $out/slimserver.pl $out/bin/slimserver
  '';

  outputs = [ "out" ];

  passthru.tests = {
    inherit (nixosTests) slimserver;
  };

  meta = with lib; {
    homepage = "https://github.com/Logitech/slimserver";
    description = "Server for Logitech Squeezebox players. This server is also called Logitech Media Server";
    # the firmware is not under a free license, but not included in the default package
    # https://github.com/Logitech/slimserver/blob/public/8.3/License.txt
    license = if enableUnfreeFirmware then licenses.unfree else licenses.gpl2Only;
    meta.mainProgram = "slimserver";
    maintainers = with maintainers; [ adamcstephens jecaro ];
    platforms = platforms.unix;
    broken = stdenv.isDarwin;
  };
}
