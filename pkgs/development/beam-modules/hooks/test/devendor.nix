{ beamPackages, runCommand }:
{
  rebarDevendorPatchHook =
    runCommand "test-rebar-devendor-patch-hook"
      {
        __structuredAttrs = true;
        nativeBuildInputs = [ beamPackages.rebarDevendorPatchHook ];
      }
      ''
        touch rebar rebar3
        printf '{deps, []}.' > rebar.config
        runHook prePatch
        test ! -e rebar
        test ! -e rebar3
        test "$(cat rebar.config)" = '{deps, []}.'
        runHook prePatch
        touch "$out"
      '';
}
