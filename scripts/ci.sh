#!/usr/bin/env bash
# Boostkit CI standard: one script, run the same way in GitHub Actions and on a
# developer machine.
#
#   ci.sh detect          print node version, package manager and the steps to run
#   ci.sh install         frozen install from the lockfile
#   ci.sh run <step>      run one of: lint typecheck test build
#   ci.sh all             install, then every detected step in order
#
# Settings come from the environment (the reusable workflow maps its inputs):
#   CI_SKIP           comma list of steps to leave out (known gaps, recorded in
#                     _HOME/sops/ci-standard.md with an issue each)
#   CI_BUILD_COMMAND  replaces "<pm> run build" (for build scripts that deploy)
#   CI_TEST_COMMAND   replaces "<pm> run test"
#   CI_NODE_VERSION   overrides the detected Node version
set -euo pipefail

cmd="${1:-all}"

pkg_field() {
  node -e '
    const p = require("./package.json");
    const path = process.argv[1].split(".");
    let v = p; for (const k of path) v = v == null ? undefined : v[k];
    if (v !== undefined) process.stdout.write(typeof v === "string" ? v : JSON.stringify(v));
  ' "$1" 2>/dev/null || true
}

has_script() { [ -n "$(pkg_field "scripts.$1")" ]; }

detect_pm() {
  if [ -f pnpm-lock.yaml ]; then echo pnpm
  elif [ -f yarn.lock ]; then echo yarn
  elif [ -f bun.lock ] || [ -f bun.lockb ]; then echo bun
  else echo npm
  fi
}

detect_node() {
  if [ -n "${CI_NODE_VERSION:-}" ]; then echo "$CI_NODE_VERSION"; return; fi
  if [ -f .nvmrc ]; then tr -d ' \r\nv' < .nvmrc; return; fi
  if [ -f .node-version ]; then tr -d ' \r\nv' < .node-version; return; fi
  local e; e="$(pkg_field engines.node)"
  # "24", "24.x", "^24", "~24.1", ">=24 <25": use that major.
  # Open ranges (">=20.9.0", ">=24") use the portfolio default, 24, which meets them.
  if [[ "$e" =~ ^[\^~]?([0-9]+)(\.[0-9x]+)*$ ]]; then echo "${BASH_REMATCH[1]}"; return; fi
  if [[ "$e" =~ ^\>=\ *([0-9]+)[^\<]*\<\ *([0-9]+) ]] && [ "$((BASH_REMATCH[2] - BASH_REMATCH[1]))" -le 1 ]; then echo "${BASH_REMATCH[1]}"; return; fi
  if [[ "$e" =~ ^\>=\ *([0-9]+) ]] && [ "${BASH_REMATCH[1]}" -gt 24 ]; then echo "${BASH_REMATCH[1]}"; return; fi
  echo 24
}

typecheck_script() {
  for s in typecheck type-check tsc; do has_script "$s" && { echo "$s"; return; }; done
  true
}

test_script() {
  local t; t="$(pkg_field scripts.test)"
  if [ -n "$t" ] && [[ "$t" != *"no test specified"* ]]; then echo test; fi
  true
}

skipped() { [[ ",${CI_SKIP:-}," == *",$1,"* ]]; }

detect_steps() {
  local steps=()
  has_script lint && ! skipped lint && steps+=(lint)
  [ -n "$(typecheck_script)" ] && ! skipped typecheck && steps+=(typecheck)
  [ -n "$(test_script)" ] && ! skipped test && steps+=(test)
  { has_script build || [ -n "${CI_BUILD_COMMAND:-}" ]; } && ! skipped build && steps+=(build)
  echo "${steps[*]:-}"
}

pmrun() {
  local pm; pm="$(detect_pm)"
  case "$pm" in
    npm) npm run "$@" ;;
    *) "$pm" run "$@" ;;
  esac
}

do_install() {
  local pm; pm="$(detect_pm)"
  case "$pm" in
    npm) npm ci ;;
    pnpm)
      if ! command -v pnpm >/dev/null 2>&1; then
        if [ -n "$(pkg_field packageManager)" ]; then corepack enable
        else
          local lv; lv="$(grep -m1 '^lockfileVersion' pnpm-lock.yaml | tr -dc '0-9.')"
          case "$lv" in 9*) npm i -g pnpm@10 ;; 6*) npm i -g pnpm@8 ;; *) npm i -g pnpm@10 ;; esac
        fi
      fi
      pnpm install --frozen-lockfile ;;
    yarn) corepack enable; yarn install --frozen-lockfile ;;
    bun) npm i -g bun; bun install --frozen-lockfile ;;
  esac
}

is_next() { [ -n "$(pkg_field dependencies.next)$(pkg_field devDependencies.next)" ]; }

do_step() {
  echo "::group::$1"
  case "$1" in
    lint) pmrun lint ;;
    typecheck)
      # Next 15.5+ writes the route types tsc needs into .next/types; a clean
      # checkout has none until a build, so generate them first.
      if is_next; then npx --no-install next typegen >/dev/null 2>&1 || echo "next typegen unavailable; typechecking without it"; fi
      pmrun "$(typecheck_script)" ;;
    test)
      if [ -n "${CI_TEST_COMMAND:-}" ]; then bash -c "$CI_TEST_COMMAND"; else pmrun test; fi ;;
    build)
      if [ -n "${CI_BUILD_COMMAND:-}" ]; then bash -c "$CI_BUILD_COMMAND"; else pmrun build; fi ;;
    *) echo "unknown step $1" >&2; exit 2 ;;
  esac
  echo "::endgroup::"
}

case "$cmd" in
  detect)
    echo "node=$(detect_node)"
    echo "pm=$(detect_pm)"
    echo "steps=$(detect_steps)"
    echo "next=$(is_next && echo true || echo false)"
    ;;
  install) do_install ;;
  run) do_step "$2" ;;
  all)
    do_install
    for s in $(detect_steps); do do_step "$s"; done
    ;;
  *) echo "usage: ci.sh detect|install|run <step>|all" >&2; exit 2 ;;
esac
