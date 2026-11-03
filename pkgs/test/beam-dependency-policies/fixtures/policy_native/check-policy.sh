#!/usr/bin/env bash
set -eu

echo BEAM_POLICY_NATIVE_COMPILER_REACHED
hello --version
pkg-config --exists zlib
read -r -a zlibFlags <<< "$(pkg-config --cflags --libs zlib)"
cc c_src/probe.c "${zlibFlags[@]}" -o probe
mkdir --parents priv
./probe > priv/zlib-version
test "$BEAM_POLICY_DEFAULT" = provided
test "$BEAM_POLICY_ENV" = caller-wins
test "$(cat policy-source)" = scoped-source-patch
printf '%s\n' "$BEAM_POLICY_DEFAULT" "$BEAM_POLICY_ENV" > priv/policy-env
