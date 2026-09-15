# shellcheck shell=bash
#
# It's common to vendor a copy of rebar/rebar3 in repos, but we want to remove those

rebarDevendorPatchHook() {
  echo "Executing rebarDevendorPatchHook"

  rm --force rebar rebar3

  echo "Finished rebarDevendorPatchHook"
}

if [ -z "${dontRebarDevendorPatch-}" ]; then
  prePatchHooks+=(rebarDevendorPatchHook)
fi
