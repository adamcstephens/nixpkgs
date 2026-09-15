{ beamPackages, stdenvNoCC }:
let
  stripTest =
    stripDebug:
    stdenvNoCC.mkDerivation {
      name = "test-beam-release-debug-${if stripDebug then "stripped" else "retained"}";
      __structuredAttrs = true;
      inherit stripDebug;
      nativeBuildInputs = [
        beamPackages.erlang
        beamPackages.mixReleaseSetupHook
      ];
      dontMixReleaseFixup = true;
      dontUnpack = true;
      dontBuild = true;
      installPhase = ''
        mkdir --parents "$out/lib"
        erlc +debug_info -o "$out/lib" ${./setup-project/erlang/src}/setup_source.erl
      '';
      doInstallCheck = true;
      installCheckPhase = ''
        erl -noshell -pa "$out/lib" -eval '
          original = setup_source:message(),
          {ok, {setup_source, [{abstract_code, ${
            if stripDebug then "no_abstract_code" else "{raw_abstract_v1, [_ | _]}"
          }}]}} =
            beam_lib:chunks("'"$out"'/lib/setup_source.beam", [abstract_code]),
          halt().
        '
      '';
    };
in
{
  releaseDebugStripped = stripTest true;
  releaseDebugRetained = stripTest false;
}
