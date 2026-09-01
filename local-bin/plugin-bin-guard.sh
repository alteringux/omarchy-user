#!/usr/bin/env bash
# shellcheck shell=bash
#
# Sourced by a plugin's bin/ helper scripts so that a non-zero exit is caught
# and handed to `omarchy-plugin-bug-report --source script`. Fire-and-forget:
# the guard never changes the script's own exit status or output.
#
# Source this LAST, after the script has installed its own traps (the guard
# chains to any existing EXIT/ERR trap rather than replacing it):
#
#     OMARCHY_PLUGIN_ID="alteringux.countdown"
#     source "$HOME/.local/bin/plugin-bin-guard.sh"
#
# Opt out for one run with OMARCHY_PLUGIN_BIN_GUARD=0.

[[ ${OMARCHY_PLUGIN_BIN_GUARD:-1} == 0 ]] && return 0 2>/dev/null || true
[[ -n ${OMARCHY_PLUGIN_ID:-} ]] || { echo "plugin-bin-guard: OMARCHY_PLUGIN_ID unset; guard disabled" >&2; return 0 2>/dev/null || true; }

set -o errtrace

__plugin_guard_script=${BASH_SOURCE[1]:-${0}}
__plugin_guard_script=${__plugin_guard_script##*/}
__plugin_guard_args="$*"
__plugin_guard_lastcmd=""
__plugin_guard_lastline=""

# Preserve whatever the host script already trapped so we extend, not clobber.
__plugin_guard_prev_exit=$(trap -p EXIT | sed "s/^trap -- '//; s/' EXIT\$//")
__plugin_guard_prev_err=$(trap -p ERR | sed "s/^trap -- '//; s/' ERR\$//")

__plugin_guard_on_err() {
  __plugin_guard_lastcmd=$BASH_COMMAND
  __plugin_guard_lastline=${BASH_LINENO[0]:-?}
  [[ -n $__plugin_guard_prev_err ]] && eval "$__plugin_guard_prev_err"
}
trap '__plugin_guard_on_err' ERR

__plugin_guard_on_exit() {
  local code=$?
  # Run the host script's own EXIT handler first, with its original $?.
  if [[ -n $__plugin_guard_prev_exit ]]; then
    ( exit "$code" ); eval "$__plugin_guard_prev_exit"
  fi
  ((code == 0)) && return 0
  command -v omarchy-plugin-bug-report >/dev/null 2>&1 || return 0

  local body
  body=$(printf '%s\n' \
    "bin script: $__plugin_guard_script" \
    "args: ${__plugin_guard_args:-(none)}" \
    "exit code: $code" \
    "failing command: ${__plugin_guard_lastcmd:-(unknown)}" \
    "at line: ${__plugin_guard_lastline:-?}")

  setsid omarchy-plugin-bug-report \
    --plugin "$OMARCHY_PLUGIN_ID" \
    --source script \
    --summary "$__plugin_guard_script exited $code: ${__plugin_guard_lastcmd:-unknown}" \
    --message "$body" >/dev/null 2>&1 &
  disown 2>/dev/null || true
  return 0
}
trap '__plugin_guard_on_exit' EXIT
