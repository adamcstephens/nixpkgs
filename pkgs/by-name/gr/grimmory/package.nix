{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  gradle_8,
  makeWrapper,
  openjdk21,
  yarn-berry_4,
  nodejs,
}:
let
  gradle = gradle_8.override { java = openjdk21; };
  yarn-berry = yarn-berry_4;

  version = "3.1.0";

  src = fetchFromGitHub {
    owner = "grimmory-tools";
    repo = "grimmory";
    tag = "v${version}";
    hash = "sha256-qBccjV+0zT34WNTjucvGC+jR6WuZGfClEMyR8YUD0iU=";
  };

  frontend = stdenvNoCC.mkDerivation (finalAttrs: {
    name = "grimmory-frontend";

    src = src + "/frontend";

    postPatch = ''
      substituteInPlace .yarnrc.yml --replace-fail 'npmMinimalAgeGate: 4320' 'npmMinimalAgeGate: 0'
      cat >> .yarnrc.yml <<EOF
      approvedGitRepositories:
        - "**"
      enableScripts: true
      EOF
    '';

    nativeBuildInputs = [
      nodejs
      yarn-berry.yarnBerryConfigHook
      yarn-berry
    ];

    env.YARN_LOCKFILE_VERSION_OVERRIDE = 8;

    missingHashes = ./missing-hashes.json;
    offlineCache = yarn-berry.fetchYarnBerryDeps {
      inherit (finalAttrs) src missingHashes;
      hash = "sha256-V5+mezZsbiytv01PGTbEKB4iYhlPtJ2IkAtsBz1ZTAw=";
    };

    buildPhase = ''
      runHook preBuild

      yarn build:prod

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      cp -r dist/grimmory/browser $out

      runHook postInstall
    '';
  });

  grimmory = stdenvNoCC.mkDerivation (final: {
    pname = "grimmory";
    inherit src version;

    postPatch = ''
      cd backend

      substituteInPlace src/main/resources/application.yaml \
        --replace-fail "'/app/data'" "\''${GRIMMORY_DATA_DIR:/var/lib/grimmory/data}" \
        --replace-fail "'/bookdrop'" "\''${GRIMMORY_BOOKDROP_DIR:/var/lib/grimmory/bookdrop}"
    '';

    nativeBuildInputs = [
      gradle
      makeWrapper
    ];

    mitmCache = gradle.fetchDeps {
      inherit (final) pname;
      pkg = grimmory;
      data = ./deps.json;
    };

    gradleBuildTask = "build";

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/share/grimmory-api
      cp build/libs/grimmory-api-*-SNAPSHOT.jar $out/share/grimmory-api/grimmory-api.jar
      ln -s ${frontend} $out/share/grimmory-ui

      makeWrapper ${lib.getExe' openjdk21 "java"} $out/bin/grimmory \
        --add-flags "-jar $out/share/grimmory-api/grimmory-api.jar"

      runHook postInstall
    '';

    passthru = { inherit frontend; };

    meta = {
      description = "Web app for hosting, managing, and exploring books, with support for PDFs, eBooks, reading progress, metadata, and stats";
      mainProgram = "grimmory";
      homepage = "https://grimmory.org/";
      license = lib.licenses.gpl3Only;
      maintainers = with lib.maintainers; [ jvanbruegge ];
      platforms = [ "x86_64-linux" ];
    };
  });
in
grimmory
