# shellcheck shell=bash

mixCompileHook() {
  echo "Executing mixCompileHook"

  runHook preBuild

  local flagsArray=()
  concatTo flagsArray mixCompileFlags
  if [ -z "${MIX_NIX_DEPS-}" ]; then
    flagsArray+=(--no-deps-check)
  fi

  mix compile "${flagsArray[@]}"

  runHook postBuild

  echo "Finished mixCompileHook"
}

if [ -z "${dontMixCompile-}" ] && [ -z "${buildPhase-}" ]; then
  buildPhase=mixCompileHook
fi
