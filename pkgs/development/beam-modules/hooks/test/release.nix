{
  beamPackages,
  stdenvNoCC,
  ripgrep,
}:
let
  cookieTest =
    name: attrs: keepCookie:
    stdenvNoCC.mkDerivation (
      {
        name = "test-beam-release-cookie-${name}";
        __structuredAttrs = true;
        nativeBuildInputs = [
          beamPackages.mixReleaseSetupHook
          ripgrep
        ];
        dontUnpack = true;
        dontBuild = true;
        installPhase = ''
          mkdir --parents "$out/bin" "$out/releases"
          printf 'test-cookie' > "$out/releases/COOKIE"
        '';
        doInstallCheck = true;
        installCheckPhase =
          if keepCookie then
            ''
              test "$(cat "$out/releases/COOKIE")" = test-cookie
            ''
          else
            ''
              test ! -e "$out/releases/COOKIE"
            '';
      }
      // attrs
    );
in
{
  releaseCookieDefault = cookieTest "default" { } false;
  releaseCookieRemove = cookieTest "remove" { removeCookie = true; } false;
  releaseCookieKeep = cookieTest "keep" { removeCookie = false; } true;
}
