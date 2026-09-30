{
  lib,
  buildNimPackage,
  fetchFromCodeberg,
  nixosTests,
  replaceVars,
  unstableGitUpdater,
}:

buildNimPackage (
  finalAttrs: prevAttrs: {
    pname = "shitter";
    version = "0-unstable-2026-09-29";

    src = fetchFromCodeberg {
      owner = "mv12star";
      repo = "shitter";
      rev = "a6ee1f0297430258ec27976df56a0c2d1a373f2e";
      hash = "sha256-fwDOrQwuKQaDu1QAWOSc08khoE/fjqWCepz52ltetUk=";
    };

    lockFile = ./lock.json;

    patches = [
      (replaceVars ./shitter-version.patch {
        inherit (finalAttrs) version;
        inherit (finalAttrs.src) rev;
        url = builtins.replaceStrings [ "archive" ".tar.gz" ] [ "commit" "" ] finalAttrs.src.url;
      })
    ];

    postBuild = ''
      nim compile ${toString finalAttrs.nimFlags} -r tools/gencss
      nim compile ${toString finalAttrs.nimFlags} -r tools/rendermd
    '';

    postInstall = ''
      mkdir -p $out/share/shitter
      cp -r public $out/share/shitter/public
      mv $out/bin/nitter $out/bin/shitter
    '';

    passthru = {
      tests = { inherit (nixosTests) shitter; };
      updateScript = unstableGitUpdater { };
    };

    meta = {
      homepage = "https://codeberg.org/mv12star/shitter";
      description = "Alternative Twitter front-end. Fork of zedeus/nitter on GitHub";
      license = lib.licenses.agpl3Only;
      maintainers = with lib.maintainers; [
        adamcstephens
      ];
      mainProgram = "shitter";
    };
  }
)
