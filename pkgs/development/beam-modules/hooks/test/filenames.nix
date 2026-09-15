{
  beamPackages,
  stdenvNoCC,
  makeWrapper,
  ripgrep,
  bbe,
  coreutils,
  lib,
}:
{
  releaseFilenames = stdenvNoCC.mkDerivation {
    name = "test-beam-release-filenames";
    __structuredAttrs = true;
    nativeBuildInputs = [
      beamPackages.mixReleaseSetupHook
      makeWrapper
      ripgrep
      bbe
    ];
    erlang = "/original-erlang";
    mixReleaseRuntimePath = lib.makeBinPath [ coreutils ];
    dontUnpack = true;
    dontBuild = true;
    installPhase = ''
      mkdir --parents "$out/bin" "$out/erts-test" "$out/data"
      executable="$out/bin/"$'space back\\slash\nline'
      cat > "$executable" <<'EOF'
      #!/usr/bin/env bash
      test -n "$PATH"
      printf '%s' "$1"
      EOF
      chmod +x "$executable"
      printf '%s' "$erlang/lib/erlang" > "$out/data/"$'text space\\slash\nline'
      printf '\0%s\0payload' "$erlang/lib/erlang" > "$out/data/"$'binary space\\slash\nline'
      touch "$out/bin/windows.bat"
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      test "$("$out/bin/"$'space back\\slash\nline' wrapped-ok)" = wrapped-ok
      test "$(cat "$out/data/"$'text space\\slash\nline')" = "$out"
      cmp <(printf '\0%s\0payload' "$out") "$out/data/"$'binary space\\slash\nline'
      test ! -e "$out/bin/windows.bat"
    '';
  };
}
