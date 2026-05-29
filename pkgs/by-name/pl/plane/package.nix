{
  lib,
  stdenv,
  fetchFromGitHub,
  nix-update-script,
  pnpm_9,
  pnpmConfigHook,
  fetchPnpmDeps,
}:
let
  pnpm = pnpm_9;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "plane";
  version = "1.3.1";
  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "makeplane";
    repo = "plane";
    tag = "v${finalAttrs.version}";
    hash = "sha256-EWd9bw0uHC0KEFwebRBJV1SNM2OHfuq90+QLSr2w3j0=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    fetcherVersion = 4;
    hash = "sha256-6hoMjdul/fH2hfkoN+/S/d6jfPCZb+KZh5G87Wugcgc=";
  };

  nativeBuildInputs = [
    pnpmConfigHook
    pnpm
  ];

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Open-source Jira, Linear, Monday, and ClickUp alternative. Plane is a modern project management platform to manage tasks, sprints, docs, and triage";
    homepage = "https://github.com/makeplane/plane";
    changelog = "https://github.com/makeplane/plane/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ ];
    mainProgram = "plane";
    platforms = lib.platforms.all;
  };
})
