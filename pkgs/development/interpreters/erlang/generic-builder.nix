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
  removeReferencesTo,
  runtimeShell,
  stdenv,
  systemd,
  unixodbc,
  wrapGAppsHook3,
  wxwidgets_3_2,
  libx11,
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
      [ wxwidgets_3_2 ]
    else
      [
        libGL
        libGLU
        wxwidgets_3_2
        libx11
      ];

  major = builtins.head (builtins.splitVersion version);

  isCross = stdenv.buildPlatform != stdenv.hostPlatform;

  crossBuildErlang = buildPackages.beam_minimal.interpreters."erlang_${major}";

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
stdenv.mkDerivation (finalAttrs: {
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

  __structuredAttrs = true;
  strictDeps = true;

  nativeBuildInputs = [
    makeWrapper
    perl
    gnum4
    libxslt
    libxml2
  ]
  ++ optionals isCross [
    crossBuildErlang
    removeReferencesTo
  ]
  ++ optionals javacSupport [ openjdk11 ]
  ++ optionals wxSupport (
    if stdenv.hostPlatform.isDarwin then
      # configure derives the -mmacosx-version-min flag from `wx-config --cc`
      [ wxwidgets_3_2 ]
    else
      [ wrapGAppsHook3 ]
  );

  buildInputs = [
    ncurses
    openssl
    zlib
  ]
  ++ optionals wxSupport wxPackages2
  ++ optionals odbcSupport [ unixodbc ]
  ++ optionals enableSystemd [ systemd ];

  # disksup requires a shell
  postPatch = ''
    substituteInPlace lib/os_mon/src/disksup.erl --replace-fail '"sh ' '"${runtimeShell} '
  ''
  + optionalString isCross ''
    patchShebangs --build erts/emulator/utils/find_cross_ycf
  '';

  debugInfo = enableDebugInfo;

  # On some machines, parallel build reliably crashes on `GEN    asn1ct_eval_ext.erl` step
  enableParallelBuilding = parallelBuild;

  configureFlags = [
    "--with-ssl=${lib.getOutput "out" openssl}"
    "--with-ssl-incl=${lib.getDev openssl}"
  ]
  # without a sysroot the crypto, ssl and ssh applications are skipped outright,
  # before --with-ssl is ever consulted
  ++ optional isCross "erl_xcomp_sysroot=/"
  ++ optional enableThreads "--enable-threads"
  ++ optional enableSmpSupport "--enable-smp-support"
  ++ optional enableKernelPoll "--enable-kernel-poll"
  ++ optional enableHipe "--enable-hipe"
  ++ optional javacSupport "--with-javac"
  ++ optional odbcSupport "--with-odbc=${unixodbc}"
  ++ optionals wxSupport [
    "--enable-wx"
    "--with-wx-config=${lib.getExe' wxwidgets_3_2 "wx-config"}"
  ]
  ++ optional enableSystemd "--enable-systemd"
  ++ optional stdenv.hostPlatform.isDarwin "--enable-darwin-64bit"
  # make[3]: *** [yecc.beam] Segmentation fault: 11
  ++ optional (stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isx86_64) "--disable-jit";

  installTargets = [
    "install"
    "install-docs"
  ];

  postInstall = ''
    ln -sv $out/lib/erlang/lib/erl_interface*/bin/erl_call $out/bin/erl_call

    wrapProgram $out/lib/erlang/bin/erl --prefix PATH ":" "${runtimePath}"
    wrapProgram $out/lib/erlang/bin/start_erl --prefix PATH ":" "${runtimePath}"
  ''
  + optionalString isCross ''
    # yecc and leex record the path of the include they pulled from the bootstrap
    find $out \( -name '*.beam' -o -name '*.erl' \) \
      -exec remove-references-to -t ${crossBuildErlang} {} +
  '';

  passthru = {
    buildErlang = if isCross then crossBuildErlang else finalAttrs.finalPackage;

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
})
