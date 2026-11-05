{
  elixir,
  erlang,
  hex,
  beamCopySourceHook,
  beamModuleInstallHook,
  mixBuildDirHook,
  mixCompileHook,
  mixAppConfigPatchHook,
  mixNixDepsSetupHook,

  cacert,
  lib,
  stdenv,
  writeText,
}:

lib.extendMkDerivation {
  constructDrv = stdenv.mkDerivation;
  excludeDrvArgNames = [
    "mixEnv"
  ];
  extendDrvArgs =
    finalAttrs:
    {
      beamDeps ? [ ],
      mixEnv ? "prod",
      mixTarget ? "host",

      # Allow passing compile time config instead of an empty config
      appConfigPath ? null,

      enableDebugInfo ? false,
      erlangCompilerOptions ? [ ],
      # Deterministic Erlang builds remove full system paths from debug information
      # among other things to keep builds more reproducible. See their docs for more:
      # https://www.erlang.org/doc/man/compile
      erlangDeterministicBuilds ? true,
      ...
    }@args:
    let
      registry = import ./hooks/mix-nix-deps.nix { inherit lib writeText; };
      dependencies = lib.listToAttrs (
        map (dependency: {
          name = dependency.beamModuleName or (dependency.packageName or (lib.getName dependency));
          value = dependency;
        }) beamDeps
      );
    in
    {
      name = "erlang${erlang.version}-${args.name}-${finalAttrs.version}";

      env = {
        ERL_COMPILER_OPTIONS =
          let
            options = erlangCompilerOptions ++ lib.optionals erlangDeterministicBuilds [ "deterministic" ];
          in
          "[${lib.concatStringsSep "," options}]";

        MIX_ENV = mixEnv;
        MIX_TARGET = mixTarget;
        MIX_BUILD_PREFIX = (if mixTarget == "host" then "" else "${mixTarget}_") + "${mixEnv}";
        MIX_DEBUG = if enableDebugInfo then 1 else 0;
        HEX_OFFLINE = 1;
        MIX_NIX_DEPS = registry dependencies;
        MIX_NIX_LOCKLESS = 1;
        mixNixElixir = "${elixir}/bin/elixir";
        beamToolchainErlang = "${erlang}/bin/erl";
        beamToolchainElixir = "${elixir}/bin/elixir";
        beamSourceGitUrl = args.src.gitRepoUrl or "";
        beamSourceGitRev = args.src.rev or "";
        beamSourceGitSubmodules =
          if builtins.isAttrs args.src && args.src ? fetchSubmodules then
            lib.boolToString args.src.fetchSubmodules
          else
            "";
        beamSourceGitRootDir = args.src.rootDir or "";

        LANG = if stdenv.hostPlatform.isLinux then "C.UTF-8" else "C";
        LC_CTYPE = if stdenv.hostPlatform.isLinux then "C.UTF-8" else "UTF-8";

        # some hooks need name-version, but we've overridden name above for the nix package
        beamModuleName = args.name;
      }
      // (args.env or { });

      __structuredAttrs = true;
      strictDeps = true;

      __darwinAllowLocalNetworking = true;

      # add to ERL_LIBS so other modules can find at runtime.
      # http://erlang.org/doc/man/code.html#code-path
      # Mix uses an explicit registry of precompiled dependencies.
      setupHook = writeText "setupHook.sh" ''
        addToSearchPath ERL_LIBS "$1/lib/erlang/lib"
      '';

      nativeBuildInputs = (args.nativeBuildInputs or [ ]) ++ [
        erlang
        elixir
        hex

        beamCopySourceHook
        beamModuleInstallHook
        mixBuildDirHook
        mixCompileHook
        mixAppConfigPatchHook
        mixNixDepsSetupHook
      ];

      propagatedBuildInputs = (args.propagatedBuildInputs or [ ]) ++ beamDeps;

      passthru = (args.passthru or { }) // {
        inherit beamDeps;
        beamModuleName = args.name;
        beamArtifact = "${finalAttrs.finalPackage}/lib/erlang/lib/${args.name}-${finalAttrs.version}";
      };
    }
    // lib.optionalAttrs (args.name == "castore") {
      postPatch = (args.postPatch or "") + ''
        cp ${cacert}/etc/ssl/certs/ca-bundle.crt priv/cacerts.pem
      '';
    };
}
