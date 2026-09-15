{ beamPackages, runCommand }:
{
  mixBuildDirHook =
    runCommand "test-mix-build-dir-hook"
      {
        __structuredAttrs = true;
        nativeBuildInputs = [ beamPackages.mixBuildDirHook ];
        env.MIX_BUILD_PREFIX = "prod";
      }
      ''
        mkdir empty-path empty-directory populated
        (
          cd empty-path
          ERL_LIBS=
          runHook preConfigure
          entries=(_build/prod/lib/*)
          test "''${#entries[@]}" -eq 0
        )
        (
          cd empty-directory
          mkdir libs
          ERL_LIBS="$PWD/libs"
          shopt -u nullglob
          runHook preConfigure
          test ! -L '_build/prod/lib/*'
        )
        (
          cd populated
          mkdir --parents 'first libs/alpha-1.0/ebin' second-libs/beta/ebin
          printf alpha > 'first libs/alpha-1.0/ebin/value'
          printf beta > second-libs/beta/ebin/value
          ERL_LIBS=":$PWD/first libs::$PWD/second-libs:"
          runHook preConfigure
          test "$(cat _build/prod/lib/alpha/ebin/value)" = alpha
          test "$(cat _build/prod/lib/beta/ebin/value)" = beta
          entries=(_build/prod/lib/*)
          test "''${#entries[@]}" -eq 2
        )
        touch "$out"
      '';
}
