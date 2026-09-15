{
  beamPackages,
  runCommand,
  stdenvNoCC,
}:
{
  sourceMutationsDisabled =
    runCommand "test-beam-source-mutations-disabled"
      {
        __structuredAttrs = true;
        nativeBuildInputs = [
          beamPackages.beamCopySourceHook
          beamPackages.mixAppConfigPatchHook
          beamPackages.rebarDevendorPatchHook
        ];
        dontBeamCopySource = true;
        dontMixAppConfigPatch = true;
        dontRebarDevendorPatch = true;
      }
      ''
        mkdir config
        printf 'upstream configuration' > config/config.exs
        printf 'vendored rebar' > rebar
        printf 'vendored rebar3' > rebar3
        runHook prePatch
        runHook postPatch
        test ! -e "$out/src"
        test "$(cat config/config.exs)" = 'upstream configuration'
        test "$(cat rebar)" = 'vendored rebar'
        test "$(cat rebar3)" = 'vendored rebar3'
        mkdir --parents "$out"
        cp rebar rebar3 config/config.exs "$out/"
      '';

  customBuildSteps = stdenvNoCC.mkDerivation {
    name = "test-beam-custom-build-steps";
    __structuredAttrs = true;
    nativeBuildInputs = [
      beamPackages.mixDepsCompileHook
      beamPackages.mixEscriptSetupHook
    ];
    dontMixDepsCompile = true;
    dontMixEscriptBuild = true;
    dontUnpack = true;
    escriptBinName = "custom-escript";
    postConfigure = ''
      printf 'custom dependency build' > dependency
    '';
    buildPhase = ''
      runHook preBuild
      cp dependency custom-escript
      runHook postBuild
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      test "$(cat "$out/bin/custom-escript")" = 'custom dependency build'
    '';
  };

  releaseFixupDisabled = stdenvNoCC.mkDerivation {
    name = "test-beam-release-fixup-disabled";
    __structuredAttrs = true;
    nativeBuildInputs = [ beamPackages.mixReleaseSetupHook ];
    dontMixReleaseFixup = true;
    dontUnpack = true;
    dontBuild = true;
    installPhase = ''
      mkdir --parents "$out/bin" "$out/releases"
      printf 'custom launcher' > "$out/bin/launcher.bat"
      printf 'test-cookie' > "$out/releases/COOKIE"
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      test "$(cat "$out/bin/launcher.bat")" = 'custom launcher'
      test ! -e "$out/releases/COOKIE"
    '';
  };
}
