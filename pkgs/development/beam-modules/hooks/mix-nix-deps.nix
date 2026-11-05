{
  lib,
  writeText,
}:
roots:
let
  dependencies = builtins.genericClosure {
    startSet = lib.mapAttrsToList (app: dependency: {
      key = toString dependency;
      inherit app dependency;
    }) roots;
    operator =
      item:
      map (dependency: {
        key = toString dependency;
        app = dependency.beamModuleName or (dependency.packageName or (lib.getName dependency));
        inherit dependency;
      }) (item.dependency.beamDeps or [ ]);
  };
  entry =
    {
      app,
      dependency,
      ...
    }:
    let
      artifact = dependency.beamArtifact or "${dependency}/lib/erlang/lib/${app}-${dependency.version}";
    in
    "${app}\t${dependency}/src\t${artifact}\n";
in
writeText "mix-nix-deps.tsv" (lib.concatMapStrings entry dependencies)
