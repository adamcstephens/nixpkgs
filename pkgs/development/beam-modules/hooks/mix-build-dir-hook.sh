# shellcheck shell=bash
#
# Symlink all dependencies found in ERL_LIBS since Elixir does not honor ERL_LIBS

mixBuildDirHook() {
  echo "Executing mixBuildDirHook"

  local lib dir dest build_dir
  local app source artifact
  local -A precompiled=()
  if [ -n "${MIX_NIX_DEPS-}" ]; then
    while IFS=$'\t' read -r app source artifact; do
      [ -n "$app" ] && precompiled["$app"]=1
    done < "$MIX_NIX_DEPS"
  fi

  mkdir -p _build/"$MIX_BUILD_PREFIX"/lib
  while IFS= read -r -d ':' lib; do
    [ -n "$lib" ] || continue
    for dir in "$lib"/*; do
      [ -d "$dir" ] || continue
      # Strip version number for directory name if it exists, so naming of
      # all libs matches what mix's expectation.
      dest=$(basename "$dir" | cut -d '-' -f1)
      build_dir="_build/$MIX_BUILD_PREFIX/lib/$dest"
      # The bootstrap creates writable overlays for registered artifacts.
      # Never link these paths directly to the immutable store.
      [ -z "${precompiled[$dest]-}" ] || continue

      # Symlink libs to _build so that mix can find them when compiling.
      # This is what allows mix to compile the package without searching
      # for dependencies over the network.
      ln -sv "$dir" "$build_dir"
    done
  done <<<"$ERL_LIBS:"

  echo "Finished mixBuildDirHook"
}

preConfigureHooks+=(mixBuildDirHook)
