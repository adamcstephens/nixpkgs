# shellcheck shell=bash
#
# Keep the Mix launcher local to this build. Subprocesses inherit both PATH and
# the registry, so every Mix invocation uses the same precompiled dependencies.

mixNixDepsPreUnpack() {
  local launcherDir="$NIX_BUILD_TOP/.mix-nix-bin"
  mkdir --parents "$launcherDir"
  printf '#!/usr/bin/env bash\nexec %q %q "$@"\n' \
    "$mixNixElixir" '@bootstrap@' > "$launcherDir/mix"
  chmod +x "$launcherDir/mix"
  patchShebangs "$launcherDir/mix"
  export PATH="$launcherDir:$PATH"
  export MIX_NIX_DEPS
}

mixNixDepsPreConfigure() {
  echo "Executing mixNixDepsPreConfigure"

  local app source artifact
  while IFS=$'\t' read -r app source artifact; do
    [ -n "$app" ] || continue
    mkdir --parents "${MIX_DEPS_PATH:-deps}"
    if [ ! -e "${MIX_DEPS_PATH:-deps}/$app" ]; then
      ln --symbolic --verbose "$source" "${MIX_DEPS_PATH:-deps}/$app"
    fi
  done < "$MIX_NIX_DEPS"

  echo "Finished mixNixDepsPreConfigure"
}

preUnpackHooks+=(mixNixDepsPreUnpack)
preConfigureHooks+=(mixNixDepsPreConfigure)
