{
  # options set through beam-packages
  # systemd support for epmd only
  systemdSupport ? null,
  wxSupport ? true,

  # options set by version specific files, e.g. 28.nix
  version,
  hash ? null,

}:
{
  # overridable options
  enableDebugInfo ? false,
  enableHipe ? true,
  enableKernelPoll ? true,
  enableSmpSupport ? true,
  enableThreads ? true,
  javacSupport ? false,
  odbcSupport ? false,
  parallelBuild ? true,

  buildPackages,
  fetchFromGitHub,
  gawk,
  gnum4,
  gnused,
  lib,
  libGL,
  libGLU,
  libxml2,
  libxslt,
  makeWrapper,
  ncurses,
  nix-update-script,
  openjdk11,
  openssl,
  perl,
  pkgsBuildBuild,
  removeReferencesTo,
  runtimeShell,
  stdenv,
  systemd,
  unixODBC,
  wrapGAppsHook3,
  wxGTK32,
  xorg,
  zlib,
}:
let
  inherit (lib)
    optional
    optionals
    optionalString
    ;

  wxPackages2 =
    if stdenv.hostPlatform.isDarwin then
      [ wxGTK32 ]
    else
      [
        libGL
        libGLU
        wxGTK32
        xorg.libX11
        wrapGAppsHook3
      ];

  major = builtins.head (builtins.splitVersion version);

  enableSystemd =
    if (systemdSupport == null) then
      lib.meta.availableOn stdenv.hostPlatform systemd
    else
      systemdSupport;

  runtimePath = lib.makeBinPath [
    gawk
    gnused
  ];
in
stdenv.mkDerivation {
  pname = "erlang" + optionalString javacSupport "_javac" + optionalString odbcSupport "_odbc";
  inherit version;

  src = fetchFromGitHub {
    owner = "erlang";
    repo = "otp";
    tag = "OTP-${version}";
    inherit hash;
  };

  env = {
    # only build man pages and shell/IDE docs
    DOC_TARGETS = "man chunks";
    LANG = "C.UTF-8";
  };

  depsBuildBuild = lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
    buildPackages.stdenv.cc
    pkgsBuildBuild.erlang
  ];

  nativeBuildInputs = [
    makeWrapper
    perl
    gnum4
    libxslt
    libxml2
    removeReferencesTo
  ];

  buildInputs = [
    ncurses
    openssl
    zlib
  ]
  ++ optionals wxSupport wxPackages2
  ++ optionals odbcSupport [ unixODBC ]
  ++ optionals javacSupport [ openjdk11 ]
  ++ optionals enableSystemd [ systemd ];

  # disksup requires a shell
  postPatch = ''
    substituteInPlace lib/os_mon/src/disksup.erl --replace-fail '"sh ' '"${runtimeShell} '
  ''
  + lib.optionalString (stdenv.hostPlatform != stdenv.buildPlatform) ''
    # When cross-compiling, patch escript shebangs to use the bootstrap Erlang
    patchShebangs --build erts/emulator/utils/find_cross_ycf
  '';

  debugInfo = enableDebugInfo;

  # On some machines, parallel build reliably crashes on `GEN    asn1ct_eval_ext.erl` step
  enableParallelBuilding = parallelBuild;

  configureFlags = [
    "--with-ssl=${lib.getOutput "out" openssl}"
    "--with-ssl-incl=${lib.getDev openssl}"
  ]
  ++ optional enableThreads "--enable-threads"
  ++ optional enableSmpSupport "--enable-smp-support"
  ++ optional enableKernelPoll "--enable-kernel-poll"
  ++ optional enableHipe "--enable-hipe"
  ++ optional javacSupport "--with-javac"
  ++ optional odbcSupport "--with-odbc=${unixODBC}"
  ++ optional (!wxSupport) "--without-wx"
  ++ optional enableSystemd "--enable-systemd"
  ++ optional stdenv.hostPlatform.isDarwin "--enable-darwin-64bit"
  # make[3]: *** [yecc.beam] Segmentation fault: 11
  ++ optional (stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isx86_64) "--disable-jit"
  # When building fully static binaries, link NIFs and SSL statically
  ++ optionals stdenv.hostPlatform.isStatic [
    "--enable-static-nifs=yes"
    "--disable-dynamic-ssl-lib"
    "--with-ssl-zlib=${zlib}/lib"
  ];

  # When building statically, the main beam binary is fully static but some
  # drivers (.so files) are still built for optional runtime loading.
  # Since a static executable cannot dlopen(), we need to handle the DED
  # (Dynamic Erlang Driver) build specially and clean up unusable .so files.
  preConfigure = lib.optionalString stdenv.hostPlatform.isStatic ''
    # Set cross-compilation sysroot so crypto/ssl can find OpenSSL
    export erl_xcomp_sysroot="${stdenv.cc.libc}"

    # Add library paths for configure link tests
    export LDFLAGS="$LDFLAGS -L${lib.getLib openssl}/lib -L${zlib}/lib"
    # Tell the build system to link crypto and zlib statically into NIFs
    export LIBS="-lcrypto -lz"

    # Get the path to the dynamic musl (not musl-static)
    muslLib=$(dirname $(dirname ${stdenv.cc.libc}/lib/libc.so))/lib

    # Create a wrapper script that uses the unwrapped compiler with dynamic CRT
    # This allows the .so files to build (they're needed during the build process)
    mkdir -p $TMPDIR/ded-wrapper

    cat > $TMPDIR/ded-wrapper/cc << WRAPPER
    #!/bin/sh
    # Use the unwrapped compiler with dynamic musl CRT for building shared objects
    exec ${stdenv.cc.cc}/bin/${stdenv.cc.targetPrefix}gcc -B$muslLib "\$@"
    WRAPPER

    chmod +x $TMPDIR/ded-wrapper/cc
    export DED_LD="$TMPDIR/ded-wrapper/cc"
    export DED_LDFLAGS="-shared -fPIC"
    export DED_CFLAGS="-fPIC"
    # For crypto configure link test - use empty flags since we're linking statically
    export DED_LDFLAGS_CONFTEST="-L${lib.getLib openssl}/lib -L${zlib}/lib"
  '';

  # Remove unusable .so files from static builds - they can't be loaded by
  # a statically linked executable anyway, and keeping them is misleading
  postInstall = ''
    ln -sv $out/lib/erlang/lib/erl_interface*/bin/erl_call $out/bin/erl_call

    wrapProgram $out/lib/erlang/bin/erl --prefix PATH ":" "${runtimePath}"
    wrapProgram $out/lib/erlang/bin/start_erl --prefix PATH ":" "${runtimePath}"
  ''
  + lib.optionalString stdenv.hostPlatform.isStatic ''
    # Remove driver .so files that cannot be loaded by the static executable
    find $out/lib/erlang -name "*.so" -delete
  '';

  postFixup = lib.optionalString stdenv.hostPlatform.isStatic ''
    # Remove propagated-build-inputs to avoid closure bloat from static libs
    rm $out/nix-support/propagated-build-inputs

    # Clean up references to build-time paths in installed files
    find $out -name "*.mk" -exec sed -i 's|-L/nix/store/[^ ]*||g' {} \;

    # Remove -file() directives in .erl source files that reference bootstrap erlang
    find $out -name "*.erl" -exec sed -i 's|-file("/nix/store/[^"]*"|-file(""|g' {} \;

    # Scrub nix store paths from .beam files (debug info contains source paths)
    for f in $(find $out -name "*.beam"); do
      sed -i "s|/nix/store/[a-z0-9]\{32\}-[^/]*/|/|g" "$f" 2>/dev/null || true
    done

    find "$out" -type f -exec remove-references-to -t ${lib.getOutput "out" openssl} '{}' +
    find "$out" -type f -exec remove-references-to -t ${lib.getDev openssl} '{}' +
    find "$out" -type f -exec remove-references-to -t ${lib.getOutput "etc" openssl} '{}' +
    find "$out" -type f -exec remove-references-to -t ${ncurses} '{}' +
    find "$out" -type f -exec remove-references-to -t ${zlib} '{}' +
  '';

  installTargets = [
    "install"
  ]
  ++ lib.optionals (!stdenv.hostPlatform.isStatic) [
    "install-docs"
  ];

  passthru = {
    updateScript = nix-update-script {
      extraArgs = [
        "--version-regex"
        "OTP-(${major}.*)"
        "--override-filename"
        "pkgs/development/interpreters/erlang/${major}.nix"
      ];
    };
  };

  meta = {
    homepage = "https://www.erlang.org/";
    downloadPage = "https://www.erlang.org/download.html";
    description = "Programming language used for massively scalable soft real-time systems";
    changelog = "https://github.com/erlang/otp/releases/tag/OTP-${version}";

    longDescription = ''
      Erlang is a programming language used to build massively scalable
      soft real-time systems with requirements on high availability.
      Some of its uses are in telecoms, banking, e-commerce, computer
      telephony and instant messaging. Erlang's runtime system has
      built-in support for concurrency, distribution and fault
      tolerance.
    '';

    platforms = lib.platforms.unix;
    teams = [ lib.teams.beam ];
    license = lib.licenses.asl20;
  };
}
