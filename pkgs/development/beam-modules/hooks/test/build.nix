{
  beamPackages,
  stdenv,
}:
let
  mixTest =
    name: attrs:
    stdenv.mkDerivation (
      {
        name = "test-${name}";
        src = ./build-project/mix;
        __structuredAttrs = true;
        env = {
          MIX_ENV = "prod";
          LANG = if stdenv.hostPlatform.isLinux then "C.UTF-8" else "C";
          LC_CTYPE = if stdenv.hostPlatform.isLinux then "C.UTF-8" else "UTF-8";
        };
        preConfigure = ''
          export HOME="$TMPDIR/home"
          mkdir --parents "$HOME"
        '';
      }
      // attrs
    );
  rebarTest =
    name: attrs:
    stdenv.mkDerivation (
      {
        name = "test-${name}";
        src = ./build-project/rebar;
        __structuredAttrs = true;
        nativeBuildInputs = [
          beamPackages.erlang
          beamPackages.rebar3
          beamPackages.rebar3CompileHook
        ];
      }
      // attrs
    );
in
{
  mixCompileHook-build = mixTest "mixCompileHook-build" {
    nativeBuildInputs = [
      beamPackages.elixir
      beamPackages.mixCompileHook
    ];
    mixCompileFlags = [ "--warnings-as-errors" ];
    preBuild = ''
      printf '%s\n' 'mix hook' > message
    '';
    postBuild = ''
      elixir -pa _build/prod/lib/build_probe/ebin --eval '
        "mix hook" = BuildProbe.message()
        File.write!("compiled-result", BuildProbe.message())
      '
    '';
    installPhase = ''
      mkdir --parents "$out"
      cp --recursive _build/prod/lib/build_probe/ebin "$out/ebin"
      cp compiled-result "$out/result"
      test "$(cat "$out/result")" = 'mix hook'
    '';
  };

  mixCompileHook-customPhase = mixTest "mixCompileHook-customPhase" {
    nativeBuildInputs = [
      beamPackages.elixir
      beamPackages.mixCompileHook
    ];
    buildPhase = ''
      printf '%s\n' 'custom mix build' > message
      mix compile --no-deps-check
    '';
    installPhase = ''
      mkdir --parents "$out"
      cp --recursive _build/prod/lib/build_probe/ebin "$out/ebin"
      elixir -pa "$out/ebin" --eval '
        "custom mix build" = BuildProbe.message()
      '
    '';
  };

  rebar3CompileHook-build = rebarTest "rebar3CompileHook-build" {
    preBuild = ''
      printf '%s\n' '-define(MESSAGE, "rebar hook").' > src/message.hrl
    '';
    postBuild = ''
      erl -noshell -pa ebin -eval '
        "rebar hook" = build_probe:message(),
        ok = file:write_file("compiled-result", build_probe:message()),
        halt().
      '
    '';
    installPhase = ''
      mkdir --parents "$out"
      cp --recursive ebin "$out/ebin"
      cp compiled-result "$out/result"
      test "$(cat "$out/result")" = 'rebar hook'
    '';
  };

  rebar3CompileHook-customPhase = rebarTest "rebar3CompileHook-customPhase" {
    buildPhase = ''
      printf '%s\n' '-define(MESSAGE, "custom erlang build").' > src/message.hrl
      mkdir --parents custom-ebin
      erlc -o custom-ebin src/build_probe.erl
    '';
    installPhase = ''
      mkdir --parents "$out"
      cp --recursive custom-ebin "$out/ebin"
      erl -noshell -pa "$out/ebin" -eval '
        "custom erlang build" = build_probe:message(),
        halt().
      '
    '';
  };

  mixDepsCompileHook-localDependency = mixTest "mixDepsCompileHook-localDependency" {
    src = ./build-project/deps;
    nativeBuildInputs = [
      beamPackages.elixir
      beamPackages.mixDepsCompileHook
    ];
    buildPhase = ''
      elixir -pa _build/prod/lib/local_probe/ebin --eval '
        "local dependency" = LocalProbe.message()
      '
      test ! -e _build/prod/lib/deps_probe/ebin/Elixir.DepsProbe.beam
      mix compile --no-deps-check
    '';
    installPhase = ''
      mkdir --parents "$out/lib"
      cp --recursive _build/prod/lib/local_probe "$out/lib/"
      cp --recursive _build/prod/lib/deps_probe "$out/lib/"
      elixir -pa "$out/lib/local_probe/ebin" -pa "$out/lib/deps_probe/ebin" --eval '
        "compiled with local dependency" = DepsProbe.message()
      '
    '';
  };

  mixEscriptSetupHook-buildAndInstall = mixTest "mixEscriptSetupHook-buildAndInstall" {
    nativeBuildInputs = [
      beamPackages.elixir
      beamPackages.erlang
      beamPackages.mixEscriptSetupHook
    ];
    escriptBinName = "hook-probe";
    buildPhase = ''
      printf '%s\n' 'escript hook' > message
      mix compile --no-deps-check
      runHook postBuild
    '';
    preInstall = ''
      test "$(escript ./hook-probe before install)" = 'escript hook: before install'
      printf '%s\n' 'before install' > install-state
    '';
    postInstall = ''
      test "$(cat install-state)" = 'before install'
      test "$(escript "$out/bin/hook-probe" after install)" = 'escript hook: after install'
      escript "$out/bin/hook-probe" installed > "$out/result"
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      test "$(escript "$out/bin/hook-probe" installed)" = 'escript hook: installed'
    '';
  };

  mixEscriptSetupHook-customInstall = mixTest "mixEscriptSetupHook-customInstall" {
    nativeBuildInputs = [
      beamPackages.elixir
      beamPackages.erlang
      beamPackages.mixEscriptSetupHook
    ];
    escriptBinName = "hook-probe";
    buildPhase = ''
      printf '%s\n' 'custom escript install' > message
      mix compile --no-deps-check
      runHook postBuild
    '';
    installPhase = ''
      mkdir --parents "$out/custom-bin"
      cp hook-probe "$out/custom-bin/"
      test "$(escript "$out/custom-bin/hook-probe" custom location)" = 'custom escript install: custom location'
      test ! -e "$out/bin"
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      test "$(escript "$out/custom-bin/hook-probe" installed)" = 'custom escript install: installed'
    '';
  };
}
