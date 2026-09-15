{
  beamPackages,
  stdenv,
  lib,
  makeWrapper,
  ripgrep,
  bbe,
  coreutils,
  gnused,
  gnugrep,
  gawk,
}:
{
  mixReleaseSetupHook = stdenv.mkDerivation {
    name = "test-mix-release-setup-hook";
    src = ./build-project/mix;
    __structuredAttrs = true;
    nativeBuildInputs = [
      beamPackages.elixir
      beamPackages.erlang
      beamPackages.mixReleaseSetupHook
      makeWrapper
      ripgrep
      bbe
    ];
    inherit (beamPackages) erlang;
    mixReleaseName = "probe";
    mixReleaseRuntimePath = lib.makeBinPath [
      coreutils
      gnused
      gnugrep
      gawk
    ];
    env = {
      MIX_ENV = "prod";
      ERL_COMPILER_OPTIONS = "[deterministic]";
      LANG = if stdenv.hostPlatform.isLinux then "C.UTF-8" else "C";
      LC_CTYPE = if stdenv.hostPlatform.isLinux then "C.UTF-8" else "UTF-8";
    };
    buildPhase = ''
      export HOME="$TMPDIR"
      printf 'release hook' > message
      mix compile --no-deps-check
    '';
    preInstall = ''
      mkdir --parents rel/overlays
      printf 'configured' > rel/overlays/settings
    '';
    postInstall = ''
      substituteInPlace "$out/settings" --replace-fail configured installed
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      test "$(cat "$out/settings")" = installed
      test ! -e "$out/releases/COOKIE"
      test "$(RELEASE_COOKIE=test-cookie "$out/bin/probe" eval 'IO.write(BuildProbe.message())')" = 'release hook'
    '';
  };
}
