{
  beamPackages,
  cacert,
  glib,
  hello,
  lib,
  pkg-config,
  runCommand,
  stdenv,
  testers,
  vips,
  zlib,
}:
let
  fixtures = ./fixtures;
  caBundle = "${cacert}/etc/ssl/certs/ca-bundle.crt";

  scoped = beamPackages.overrideScope (
    _final: prev: {
      beamDependencyPolicies = prev.beamDependencyPolicies // {
        policy_native = {
          nativeBuildInputs = [
            hello
            pkg-config
            stdenv.cc
          ];
          buildInputs = [ zlib ];
          env = {
            BEAM_POLICY_DEFAULT = "provided";
            BEAM_POLICY_ENV = "policy-default";
          };
          sourcePatch = ''
            mkdir --parents priv
            printf '%s\n' scoped-source-patch > policy-source
          '';
        };
      };
    }
  );

  castore = beamPackages.buildMix {
    name = "castore";
    version = "0.1.0";
    src = fixtures + /castore;
    # The policy must run after package-specific patching, not just unpacking.
    postPatch = ''
      printf '%s\n' package-patched-certificates > priv/cacerts.pem
    '';
    postBuild = ''
      cmp priv/cacerts.pem ${caBundle}
    '';
  };

  certifi = beamPackages.buildRebar3 {
    name = "certifi";
    version = "0.1.0";
    src = fixtures + /certifi;
    postPatch = ''
      printf '%s\n' package-patched-certificates > priv/cacerts.pem
    '';
    postBuild = ''
      cmp priv/cacerts.pem ${caBundle}
    '';
  };

  nativeArgs = {
    name = "policy_native";
    version = "0.1.0";
    src = fixtures + /policy_native;
    env.BEAM_POLICY_ENV = "caller-wins";
  };
  nativeMix = scoped.buildMix nativeArgs;
  nativeRebar = scoped.buildRebar3 nativeArgs;
  nativeErlangMk = scoped.buildErlangMk nativeArgs;

  caDeps = runCommand "beam-policy-local-ca-deps" { } ''
    mkdir --parents "$out"
    cp --recursive ${fixtures}/castore ${fixtures}/certifi "$out/"
  '';
  nativeDeps = runCommand "beam-policy-local-native-deps" { } ''
    mkdir --parents "$out"
    cp --recursive ${fixtures}/policy_native "$out/"
  '';
  emptyDeps = runCommand "beam-policy-local-empty-deps" { } ''
    mkdir --parents "$out"
  '';

  releaseArgs = {
    pname = "beam-policy-release";
    version = "0.1.0";
    src = fixtures + /release;
  };
  caMultiRelease = beamPackages.mixRelease (
    releaseArgs
    // {
      mixNixDeps = { inherit castore certifi; };
    }
  );
  caFodRelease = beamPackages.mixRelease (
    releaseArgs
    // {
      mixFodDeps = caDeps;
      # These are the writable copies. The original dependency tree stays intact.
      postPatch = ''
        printf '%s\n' package-patched-certificates > "$MIX_DEPS_PATH/castore/priv/cacerts.pem"
        printf '%s\n' package-patched-certificates > "$MIX_DEPS_PATH/certifi/priv/cacerts.pem"
      '';
      postBuild = ''
        cmp "$MIX_DEPS_PATH/castore/priv/cacerts.pem" ${caBundle}
        cmp "$MIX_DEPS_PATH/certifi/priv/cacerts.pem" ${caBundle}
      '';
    }
  );
  nativeReleaseArgs = releaseArgs // {
    env = {
      BEAM_POLICY_TEST_DEPS = "native";
      BEAM_POLICY_ENV = "caller-wins";
    };
  };
  nativeMultiRelease = scoped.mixRelease (
    nativeReleaseArgs
    // {
      mixNixDeps.policy_native = nativeMix;
    }
  );
  nativeFodRelease = scoped.mixRelease (
    nativeReleaseArgs
    // {
      mixFodDeps = nativeDeps;
      beamNativePolicies = [ "policy_native" ];
    }
  );

  checkCaRelease =
    name: release:
    runCommand name
      {
        nativeBuildInputs = [ beamPackages.elixir ];
      }
      ''
        cmp ${release}/lib/castore-0.1.0/priv/cacerts.pem ${caBundle}
        cmp ${release}/lib/certifi-0.1.0/priv/cacerts.pem ${caBundle}
        elixir -pa ${release}/lib/castore-0.1.0/ebin --eval \
          'unless CAStore.certificates() == File.read!("${caBundle}"), do: raise("unpatched compile-time CA bundle")'
        touch "$out"
      '';

  checkNative =
    name: package: appPath:
    runCommand name { } ''
      test -s ${package}/${appPath}/priv/zlib-version
      printf '%s\n' provided caller-wins > expected-env
      cmp ${package}/${appPath}/priv/policy-env expected-env
      touch "$out"
    '';

  omittedPolicy = testers.testBuildFailure (
    scoped.mixRelease (nativeReleaseArgs // { mixFodDeps = nativeDeps; })
  );
  unknownPolicy = builtins.tryEval (
    (scoped.mixRelease (
      releaseArgs
      // {
        mixFodDeps = emptyDeps;
        beamNativePolicies = [ "not_a_registered_policy" ];
        env.BEAM_POLICY_TEST_DEPS = "empty";
      }
    )).drvPath
  );
  emptyScope = beamPackages.overrideScope (_final: _prev: { beamDependencyPolicies = { }; });
in
{
  ca-multi-artifacts = runCommand "beam-policy-ca-multi-artifacts" { } ''
    cmp ${castore}/src/priv/cacerts.pem ${caBundle}
    cmp ${castore}/lib/erlang/lib/castore-0.1.0/priv/cacerts.pem ${caBundle}
    cmp ${certifi}/src/priv/cacerts.pem ${caBundle}
    cmp ${certifi}/lib/erlang/lib/certifi-0.1.0/priv/cacerts.pem ${caBundle}
    touch "$out"
  '';

  ca-multi-release = checkCaRelease "beam-policy-ca-multi-release" caMultiRelease;
  ca-fod-release = checkCaRelease "beam-policy-ca-fod-release" caFodRelease;

  ca-fod-preserves-input = runCommand "beam-policy-ca-fod-preserves-input" { } ''
    test -d ${caFodRelease}
    printf '%s\n' 'unpatched castore certificates' > expected-castore
    printf '%s\n' 'unpatched certifi certificates' > expected-certifi
    cmp ${caDeps}/castore/priv/cacerts.pem expected-castore
    cmp ${caDeps}/certifi/priv/cacerts.pem expected-certifi
    touch "$out"
  '';

  native-mix = checkNative "beam-policy-native-mix" nativeMix "lib/erlang/lib/policy_native-0.1.0";
  native-rebar =
    checkNative "beam-policy-native-rebar" nativeRebar
      "lib/erlang/lib/policy_native-0.1.0";
  native-erlang-mk =
    checkNative "beam-policy-native-erlang-mk" nativeErlangMk
      "lib/erlang/lib/policy_native";
  native-multi-release =
    checkNative "beam-policy-native-multi-release" nativeMultiRelease
      "lib/policy_native-0.1.0";
  native-fod-release =
    checkNative "beam-policy-native-fod-release" nativeFodRelease
      "lib/policy_native-0.1.0";

  native-source-export = runCommand "beam-policy-native-source-export" { } ''
    printf '%s\n' scoped-source-patch > expected
    cmp ${nativeMix}/src/policy-source expected
    cmp ${nativeRebar}/src/policy-source expected
    # The source export precedes compilation, unlike the installed priv directory.
    test ! -e ${nativeMix}/src/priv/zlib-version
    test ! -e ${nativeRebar}/src/priv/zlib-version
    touch "$out"
  '';

  fod-missing-selection = runCommand "beam-policy-fod-missing-selection" { } ''
    grep --fixed-strings policy_native ${omittedPolicy}/testBuildFailure.log
    grep --fixed-strings beamNativePolicies ${omittedPolicy}/testBuildFailure.log
    ! grep --fixed-strings 'Executing mixDepsCompileHook' ${omittedPolicy}/testBuildFailure.log
    ! grep --fixed-strings BEAM_POLICY_NATIVE_COMPILER_REACHED ${omittedPolicy}/testBuildFailure.log
    touch "$out"
  '';

  unknown-selection =
    assert !unknownPolicy.success;
    runCommand "beam-policy-unknown-selection" { } ''
      touch "$out"
    '';

  absent-selected-dependency = scoped.mixRelease (
    releaseArgs
    // {
      pname = "beam-policy-absent-selected-dependency";
      mixFodDeps = emptyDeps;
      beamNativePolicies = [ "policy_native" ];
      env.BEAM_POLICY_TEST_DEPS = "empty";
    }
  );

  empty-registry = emptyScope.mixRelease (
    releaseArgs
    // {
      pname = "beam-policy-empty-registry";
      mixFodDeps = emptyDeps;
      env.BEAM_POLICY_TEST_DEPS = "empty";
    }
  );

  builtin-vix-policy =
    let
      policy = beamPackages.beamDependencyPolicies.vix;
    in
    assert lib.elem pkg-config policy.nativeBuildInputs;
    assert lib.elem vips policy.buildInputs;
    assert lib.elem glib.dev policy.buildInputs;
    assert policy.env.VIX_COMPILATION_MODE == "PLATFORM_PROVIDED_LIBVIPS";
    runCommand "beam-policy-builtin-vix" { } ''
      touch "$out"
    '';
}
