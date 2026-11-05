# shellcheck shell=bash

mixEscriptBuild() {
  echo "Executing mixEscriptBuild"

  local flags=()
  if [ -z "${MIX_NIX_DEPS-}" ]; then
    flags+=(--no-deps-check)
  fi
  mix escript.build "${flags[@]}"

  echo "Finished mixEscriptBuild"
}

mixEscriptInstall() {
  echo "Executing mixEscriptInstall"

  runHook preInstall

  mkdir -p "$out/bin"
  cp "$escriptBinName" "$out/bin"

  runHook postInstall

  echo "Finished mixEscriptInstall"
}

if [ -z "${dontMixEscriptBuild-}" ]; then
  postBuildHooks+=(mixEscriptBuild)
fi

if [ -z "${dontMixEscriptInstall-}" ] && [ -z "${installPhase-}" ]; then
  installPhase=mixEscriptInstall
fi
