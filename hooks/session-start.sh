#!/usr/bin/env bash
# SessionStart hook: when STE mode is on, load the full rule set as context.
# Runs under Claude Code, Codex, Copilot CLI and Antigravity CLI. common.sh picks the output format.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

input="$(cat 2>/dev/null)"
ste_project_from_input "$input"

mode="$(ste_mode)"
[ "$mode" = "off" ] && exit 0
cmd="$(ste_cmd)"

text="$(
  printf 'SIMPLE ENGLISH (ASD-STE100) MODE ACTIVE. Level: %s.\n' "$mode"
  printf 'This mode is enforced by a hook on every prompt. It stays active until the user types "%s off".\n' "$cmd"
  if [ "$mode" = "strict" ]; then
    printf 'STRICT: a linter checks each reply. If the reply fails, you must rewrite it before you stop.\n'
  fi
  printf 'Toggle: %s on | %s strict | %s off | %s status\n' "$cmd" "$cmd" "$cmd" "$cmd"
  if [ "$STE_HARNESS_NAME" = "claude" ] && ! ste_badge_installed; then
    printf 'The [STE] status line badge is not installed. If the user asks for it, run: bash "%s/statusline-install.sh"\n' "$STE_DIR"
  fi
  printf '\n'
  ste_rules_text
)"
ste_emit SessionStart "$text" "STE mode: $mode"
exit 0
