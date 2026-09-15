{
  beamPackages,
  lib,
  runCommand,
  stdenv,
}:
let
  mixEnv = {
    MIX_ENV = "prod";
    LANG = if stdenv.hostPlatform.isLinux then "C.UTF-8" else "C";
    LC_CTYPE = if stdenv.hostPlatform.isLinux then "C.UTF-8" else "UTF-8";
  };

  configTest =
    supplied:
    stdenv.mkDerivation (
      {
        name = "test-mixAppConfigPatchHook-${if supplied then "supplied" else "default"}";
        src = ./setup-project/mix;
        __structuredAttrs = true;
        nativeBuildInputs = [
          beamPackages.mixAppConfigPatchHook
          beamPackages.elixir
        ];
        env = mixEnv;
        buildPhase = ''
          runHook preBuild
          export HOME="$TMPDIR"
          mix compile --no-deps-check
          elixir -pa _build/prod/lib/setup_project/ebin --eval '
            ${if supplied then ":supplied" else ":default"} = SetupProject.message()
          '
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir --parents "$out"
          cp --recursive _build/prod/lib/setup_project/ebin "$out/"
          runHook postInstall
        '';
      }
      // lib.optionalAttrs supplied { appConfigPath = ./setup-project/config; }
    );

  nixDependency = runCommand "setup-hook-nix-dependency" { } ''
    mkdir --parents "$out/src"
    cp --recursive ${./setup-project/deps/setup_dep}/. "$out/src/"
  '';
in
{
  beamCopySourceHook = stdenv.mkDerivation {
    name = "test-beamCopySourceHook";
    src = ./setup-project/erlang;
    patches = [ ./setup-project/source.patch ];
    __structuredAttrs = true;
    nativeBuildInputs = [
      beamPackages.beamCopySourceHook
      beamPackages.erlang
    ];
    buildPhase = ''
      runHook preBuild
      mkdir --parents ebin
      erlc -o ebin src/setup_source.erl
      erl -noshell -pa ebin -eval 'patched = setup_source:message(), halt().'
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      test ! -e "$out/src/ebin"
      mkdir --parents "$TMPDIR/copied-source-consumer"
      erlc -o "$TMPDIR/copied-source-consumer" "$out/src/src/setup_source.erl"
      erl -noshell -pa "$TMPDIR/copied-source-consumer" \
        -eval 'patched = setup_source:message(), halt().'
      cmp src/setup_source.app.src "$out/src/src/setup_source.app.src"
      runHook postInstall
    '';
  };

  beamModuleInstallHookMix = stdenv.mkDerivation {
    name = "test-beamModuleInstallHook-mix";
    version = "1.0.0";
    src = ./setup-project/mix;
    __structuredAttrs = true;
    nativeBuildInputs = [
      beamPackages.beamModuleInstallHook
      beamPackages.elixir
    ];
    env = mixEnv // {
      beamModuleName = "setup_project";
      MIX_BUILD_PREFIX = "prod";
    };
    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      mix compile --no-deps-check
      test -L _build/prod/lib/setup_project/priv
      mkdir --parents _build/shared/lib/setup_project/src
      cp lib/setup_project.ex _build/shared/lib/setup_project/src/
      runHook postBuild
    '';
    postInstall = ''
      installed="$out/lib/erlang/lib/setup_project-1.0.0"
      test ! -L "$installed/priv"
      cmp include/setup_project.hrl "$installed/include/setup_project.hrl"
      cmp lib/setup_project.ex "$installed/src/setup_project.ex"
      rm --recursive priv _build
      elixir -pa "$installed/ebin" --eval '
        :original = SetupProject.message()
        path = Path.join(:code.priv_dir(:setup_project), "message.txt")
        "installed resource\n" = File.read!(path)
      '
    '';
  };

  beamModuleInstallHookRebar = stdenv.mkDerivation {
    name = "test-beamModuleInstallHook-rebar";
    version = "1.0.0";
    src = ./setup-project/erlang;
    __structuredAttrs = true;
    nativeBuildInputs = [
      beamPackages.beamModuleInstallHook
      beamPackages.erlang
    ];
    env.beamModuleName = "setup_source";
    buildPhase = ''
      runHook preBuild
      mkdir --parents ebin
      erlc -o ebin src/setup_source.erl
      cp src/setup_source.app.src ebin/setup_source.app
      mv priv resources
      ln --symbolic resources priv
      runHook postBuild
    '';
    postInstall = ''
      installed="$out/lib/erlang/lib/setup_source-1.0.0"
      test ! -L "$installed/priv"
      cmp include/setup_source.hrl "$installed/include/setup_source.hrl"
      rm --recursive ebin resources
      erl -noshell -pa "$installed/ebin" -eval '
        original = setup_source:message(),
        Path = filename:join(code:priv_dir(setup_source), "message.txt"),
        {ok, <<"installed resource\n">>} = file:read_file(Path),
        halt().
      '
    '';
  };

  mixAppConfigPatchHookDefault = configTest false;
  mixAppConfigPatchHookSupplied = configTest true;

  mixFodDepsSetupHook = stdenv.mkDerivation {
    name = "test-mixFodDepsSetupHook";
    src = ./setup-project/consumer;
    mixFodDeps = ./setup-project/deps;
    __structuredAttrs = true;
    nativeBuildInputs = [
      beamPackages.mixFodDepsSetupHook
      beamPackages.elixir
    ];
    env = mixEnv;
    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      test -L deps
      printf 'writable dependency asset\n' > "$MIX_DEPS_PATH/setup_dep/assets/message.txt"
      printf 'writable dependency asset\n' | cmp - deps/setup_dep/assets/message.txt
      printf 'dependency asset\n' | cmp - ${./setup-project/deps/setup_dep/assets/message.txt}
      mix deps.compile
      elixir -pa _build/prod/lib/setup_dep/ebin --eval ':dependency = SetupDep.message()'
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir --parents "$out"
      cp --recursive _build/prod/lib/setup_dep/ebin "$out/"
      cp deps/setup_dep/assets/message.txt "$out/"
      runHook postInstall
    '';
  };

  mixNixDepsSetupHook = stdenv.mkDerivation {
    name = "test-mixNixDepsSetupHook";
    src = ./setup-project/consumer;
    mixNixDeps.setup_dep = nixDependency;
    __structuredAttrs = true;
    nativeBuildInputs = [
      beamPackages.mixNixDepsSetupHook
      beamPackages.elixir
    ];
    env = mixEnv;
    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      mix deps.compile
      elixir -pa _build/prod/lib/setup_dep/ebin --eval '
        :dependency = SetupDep.message()
        "dependency asset\n" = File.read!("deps/setup_dep/assets/message.txt")
      '
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir --parents "$out"
      cp --recursive _build/prod/lib/setup_dep/ebin "$out/"
      cp deps/setup_dep/assets/message.txt "$out/"
      runHook postInstall
    '';
  };
}
