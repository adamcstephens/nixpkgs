{
  lib,
  makeSetupHook,
  tests,
}:
{
  beamCopySourceHook = makeSetupHook {
    name = "beam-copy-source-hook.sh";
    meta.license = lib.licenses.mit;
    passthru.tests = {
      test = tests.beam-hooks.beamCopySourceHook;
      disabled = tests.beam-hooks.sourceMutationsDisabled;
    };
  } ./beam-copy-source-hook.sh;

  beamModuleInstallHook = makeSetupHook {
    name = "beam-module-install-hook.sh";
    meta.license = lib.licenses.mit;
    passthru.tests = {
      mix = tests.beam-hooks.beamModuleInstallHookMix;
      rebar = tests.beam-hooks.beamModuleInstallHookRebar;
    };
  } ./beam-module-install-hook.sh;

  mixAppConfigPatchHook = makeSetupHook {
    name = "mix-config-patch-hook.sh";
    meta.license = lib.licenses.mit;
    passthru.tests = {
      defaultConfig = tests.beam-hooks.mixAppConfigPatchHookDefault;
      suppliedConfig = tests.beam-hooks.mixAppConfigPatchHookSupplied;
      disabled = tests.beam-hooks.sourceMutationsDisabled;
    };
  } ./mix-app-config-patch-hook.sh;

  mixBuildDirHook = makeSetupHook {
    name = "mix-configure-hook.sh";
    meta.license = lib.licenses.mit;
    passthru.tests.test = tests.beam-hooks.mixBuildDirHook;
  } ./mix-build-dir-hook.sh;

  mixCompileHook = makeSetupHook {
    name = "mix-compile-hook.sh";
    meta.license = lib.licenses.mit;
  } ./mix-compile-hook.sh;

  mixDepsCompileHook = makeSetupHook {
    name = "mix-deps-compile-hook.sh";
    meta.license = lib.licenses.mit;
  } ./mix-deps-compile-hook.sh;

  mixEscriptSetupHook = makeSetupHook {
    name = "mix-escript-setup-hook.sh";
    meta.license = lib.licenses.mit;
  } ./mix-escript-setup-hook.sh;

  mixFodDepsSetupHook = makeSetupHook {
    name = "mix-fod-deps-setup-hook";
    meta.license = lib.licenses.mit;
    passthru.tests.test = tests.beam-hooks.mixFodDepsSetupHook;
  } ./mix-fod-deps-setup-hook.sh;

  mixNixDepsSetupHook = makeSetupHook {
    name = "mix-nix-deps-setup-hook";
    meta.license = lib.licenses.mit;
    passthru.tests.test = tests.beam-hooks.mixNixDepsSetupHook;
  } ./mix-nix-deps-setup-hook.sh;

  mixReleaseSetupHook = makeSetupHook {
    name = "mix-release-setup-hook.sh";
    meta.license = lib.licenses.mit;
  } ./mix-release-setup-hook.sh;

  rebar3CompileHook = makeSetupHook {
    name = "rebar3-compile-hook.sh";
    meta.license = lib.licenses.mit;
  } ./rebar3-compile-hook.sh;

  rebarDevendorPatchHook = makeSetupHook {
    name = "rebar-devendor-patch-hook.sh";
    meta.license = lib.licenses.mit;
    passthru.tests = {
      test = tests.beam-hooks.rebarDevendorPatchHook;
      disabled = tests.beam-hooks.sourceMutationsDisabled;
    };
  } ./rebar-devendor-patch-hook.sh;
}
