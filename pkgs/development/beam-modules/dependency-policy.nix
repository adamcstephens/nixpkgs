{
  lib,
  beamDependencyPolicies,
  makeSetupHook,
  writeText,
}:

{
  names,
  fod ? false,
}:

let
  requiresInputs =
    policy: (policy.nativeBuildInputs or [ ]) != [ ] || (policy.buildInputs or [ ]) != [ ];
  automaticNames = builtins.attrNames (
    lib.filterAttrs (_: policy: !requiresInputs policy) beamDependencyPolicies
  );
  selectedNames = lib.unique (names ++ lib.optionals fod automaticNames);
  policies = map (
    name:
    if fod then
      beamDependencyPolicies.${name}
        or (throw "Unknown BEAM dependency policy \"${name}\" in beamNativePolicies.")
    else
      beamDependencyPolicies.${name} or { }
  ) selectedNames;
  patch = name: beamDependencyPolicies.${name}.sourcePatch or ":";
  sourcePatch =
    if fod then
      lib.concatMapStringsSep "\n" (
        name:
        let
          selected = builtins.elem name selectedNames;
        in
        ''
          if [[ -d "$MIX_DEPS_PATH"/${lib.escapeShellArg name} ]]; then
            ${
              if selected then
                ''
                  (
                    cd "$MIX_DEPS_PATH"/${lib.escapeShellArg name}
                    ${patch name}
                  )
                ''
              else
                ''
                  echo ${lib.escapeShellArg "Dependency \"${name}\" requires the \"${name}\" policy module. Add it to beamNativePolicies."} >&2
                  exit 1
                ''
            }
          fi
        ''
      ) (builtins.attrNames beamDependencyPolicies)
    else
      lib.concatMapStringsSep "\n" (
        name: beamDependencyPolicies.${name}.sourcePatch or ":"
      ) selectedNames;
in
{
  nativeBuildInputs = lib.concatMap (policy: policy.nativeBuildInputs or [ ]) policies;
  buildInputs = lib.concatMap (policy: policy.buildInputs or [ ]) policies;
  env = lib.foldl' (env: policy: env // (policy.env or { })) { } policies;

  hook =
    makeSetupHook
      {
        name = "beam-dependency-policy-hook";
        meta.license = lib.licenses.mit;
      }
      (
        writeText "beam-dependency-policy-hook.sh" ''
          beamDependencyPolicyPostPatch() {
            :
            ${sourcePatch}
          }

          postPatchHooks+=(beamDependencyPolicyPostPatch)
        ''
      );
}
