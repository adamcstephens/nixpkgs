{
  cacert,
  fetchFromGitHub,
  gettext,
  gst_all_1,
  lib,
  nix-update-script,
  python314Packages,
  qt6,
  stdenv,
  writableTmpDirAsHomeHook,
}:

let
  python3Packages = python314Packages;
  pyqt6 = python3Packages.pyqt6;
in
python3Packages.buildPythonApplication (finalAttrs: {
  pname = "picard";
  version = "3.0.0b4";
  pyproject = true;
  strictDeps = true;
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "metabrainz";
    repo = "picard";
    tag = "release-${finalAttrs.version}";
    hash = "sha256-+9IUOQGJse2KBtLTVgf6IKagSjCwDAEDOxW+ZNFphv0=";
  };

  nativeBuildInputs = [
    gettext
    qt6.wrapQtAppsHook
    python3Packages.setuptools
  ];

  buildInputs = [
    qt6.qtbase
  ]
  ++ lib.optionals (lib.meta.availableOn stdenv.hostPlatform qt6.qtwayland) [
    qt6.qtwayland
  ]
  ++ lib.optionals (pyqt6.multimediaEnabled) (
    [
      qt6.qtmultimedia
      gst_all_1.gst-libav
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good
    ]
    ++ lib.optionals (lib.meta.availableOn stdenv.hostPlatform gst_all_1.gst-vaapi) [
      gst_all_1.gst-vaapi
    ]
  );

  # pythonRelaxDeps = lib.optionals stdenv.hostPlatform.isDarwin [
  #   # Should be resolved in the next version
  #   "pyobjc-core"
  #   "pyobjc-framework-Cocoa"
  # ];

  dependencies =
    with python3Packages;
    [
      charset-normalizer
      discid
      markdown
      mutagen
      pygit2
      pyjwt
      pyqt6
      pyyaml
      tomli
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      pyobjc-core
      pyobjc-framework-Cocoa
      # pyobjc-framework-MediaPlayer
    ];

  # # Not reporting any of these issues because the next upstream version will
  # # include many breaking changes and this might not be relevant.
  # disabledTestPaths = lib.optionals stdenv.hostPlatform.isDarwin [
  #   "test/test_const_appdirs.py::AppPathsTest::test_cache_folder_macos" # - AssertionError: '/nix/var/nix/builds/nix-54642-966088698/.h[33 chars]card' ...
  #   "test/test_const_appdirs.py::AppPathsTest::test_config_folder_macos" # - AssertionError: '/nix/var/nix/builds/nix-54642-966088698/.h[38 chars]card' ...
  #   "test/test_const_appdirs.py::AppPathsTest::test_plugin_folder_macos" # - AssertionError: '/nix/var/nix/builds/nix-54642-966088698/.h[46 chars]gins' ...
  #   "test/test_plugins.py" # Various PermissionError for /var/empty/Library - hopefully will be resolved in the next release.
  #   "test/test_utils.py::HiddenFileTest::test_macos" # - FileNotFoundError: [Errno 2] No such file or directory: 'SetFile'
  # ];

  setupPyGlobalFlags = [
    "build"
    "--disable-autoupdate"
    "--localedir=${placeholder "out"}/share/locale"
  ];

  nativeCheckInputs = [
    python3Packages.pytestCheckHook
    writableTmpDirAsHomeHook
  ];
  doCheck = true;

  # pygit2 >= 1.19 loads OpenSSL certificate locations at import time, which
  # fails in the build sandbox without a CA bundle available.
  env.SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

  # In order to spare double wrapping, we use:
  preFixup = ''
    makeWrapperArgs+=("''${qtWrapperArgs[@]}")
  ''
  + lib.optionalString (pyqt6.multimediaEnabled) ''
    makeWrapperArgs+=(--prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "$GST_PLUGIN_SYSTEM_PATH_1_0")
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--version-regex"
      "release-(.*)"
    ];
  };

  meta = {
    homepage = "https://picard.musicbrainz.org";
    changelog = "https://picard.musicbrainz.org/changelog";
    description = "Official MusicBrainz tagger";
    mainProgram = "picard";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.all;
    maintainers = with lib.maintainers; [ doronbehar ];
  };
})
