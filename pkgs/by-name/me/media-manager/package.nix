{
  lib,
  python3,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "media-manager";
  version = "1.8.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "maxdorninger";
    repo = "MediaManager";
    rev = version;
    hash = "sha256-LJ2Pbkzdb5LYCn57lQgoRC19L0EtqdVfggXI2G677QY=";
  };

  build-system = [
    python3.pkgs.setuptools
    python3.pkgs.wheel
  ];

  dependencies = with python3.pkgs; [
    alembic
    apscheduler
    bencoder
    cachetools
    fastapi
    # fastapi-restful
    # fastapi-users
    # fastapi-utils
    httpx
    httpx-oauth
    jsonschema
    # libtorrent
    patool
    pillow
    pillow-avif-plugin
    psycopg
    pydantic
    pydantic-settings
    pytest
    python-json-logger
    qbittorrent-api
    requests
    # sabnzbd-api
    sqlalchemy
    starlette
    tmdbsimple
    transmission-rpc
    # tvdb-v4-official
    typing-inspect
    uvicorn
  ];

  pythonImportsCheck = [
    "mediamanager"
  ];

  meta = {
    description = "A modern selfhosted media management system for your media library";
    homepage = "https://github.com/maxdorninger/MediaManager";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ ];
    mainProgram = "media-manager";
  };
}
