#!/usr/bin/env bash
# Pre-flight a repo the way CI will see it: a fresh shallow clone of origin/main
# (no .env files), frozen install, then the detected steps.
#
#   local-check.sh <owner/repo> <workdir> [KEY=value ...]
#
# CI_SKIP / CI_BUILD_COMMAND / CI_TEST_COMMAND are read from the environment as
# in the workflow. Extra KEY=value arguments are the dummy build-time variables.
set -uo pipefail
repo="$1"; work="$2"; shift 2
here="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$work"
git clone -q --depth 1 "https://github.com/$repo.git" "$work" || exit 10
cd "$work"
for kv in "$@"; do export "$kv"; done
export CI=true NEXT_TELEMETRY_DISABLED=1 npm_config_allow_remote=root
# Keys that could send email or cost money must never reach a local run.
unset RESEND_API_KEY TYPESAFE_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY
bash "$here/ci.sh" detect
bash "$here/ci.sh" install > ../"$(basename "$work")".install.log 2>&1 || { echo "RESULT install=FAIL"; tail -30 ../"$(basename "$work")".install.log; exit 1; }
rc=0
for s in $(bash "$here/ci.sh" detect | sed -n 's/^steps=//p'); do
  if bash "$here/ci.sh" run "$s" > ../"$(basename "$work")".$s.log 2>&1; then echo "RESULT $s=ok"
  else echo "RESULT $s=FAIL"; tail -40 ../"$(basename "$work")".$s.log; rc=1; fi
done
exit $rc
