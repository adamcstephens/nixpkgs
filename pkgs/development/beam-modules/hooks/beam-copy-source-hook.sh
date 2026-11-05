# shellcheck shell=bash
#
# Copy the source so it can be used by mix projects to assemble `deps`
# do this before building to avoid build artifacts but after patching
# to include any user modifications to the source

beamCopySourceHook() {
  echo "Executing beamCopySourceHook"

  mkdir -p "$out/src"
  cp -r "." "$out/src"

  mkdir --parents "$out/nix-support"
  local gitUrl="${beamSourceGitUrl-}" gitRev="${beamSourceGitRev-}" gitOrigin
  if [ -e "$out/src/.git" ]; then
    gitRev=$(git -C "$out/src" rev-parse HEAD)
    gitOrigin=$(git -C "$out/src" config --get remote.origin.url || true)
    if [ -n "$gitOrigin" ]; then
      gitUrl="$gitOrigin"
    fi
  fi
  if [[ "$gitRev" =~ ^[[:xdigit:]]{40}$ ]] && [ -n "$gitUrl" ]; then
    printf '%s\t%s\n' "$gitUrl" "$gitRev" > "$out/nix-support/git-info"
    if [ ! -e "$out/src/.git" ] && [ -n "${beamSourceGitSubmodules-}" ]; then
      printf 'submodules\t%s\nrootDir\t%s\n' \
        "$beamSourceGitSubmodules" "${beamSourceGitRootDir-}" \
        > "$out/nix-support/git-fetch-options"
    fi
  fi

  if [ -n "${beamToolchainErlang-}" ]; then
    "$beamToolchainErlang" -noshell \
      -eval 'io:format("otp\t~s~n", [erlang:system_info(otp_release)]), halt().' \
      > "$out/nix-support/beam-toolchain"
  fi
  if [ -n "${beamToolchainElixir-}" ]; then
    "$beamToolchainElixir" --eval 'IO.puts("elixir\t#{System.version()}")' \
      >> "$out/nix-support/beam-toolchain"
  fi

  echo "Finished beamCopySourceHook"
}

if [ -z "${dontBeamCopySource-}" ]; then
  postPatchHooks+=(beamCopySourceHook)
fi
