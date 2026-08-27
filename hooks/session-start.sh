#!/usr/bin/env bash
# SessionStart hook: when STE mode is on, load the full rule set as context.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

mode="$(ste_mode)"
[ "$mode" = "off" ] && exit 0

{
  printf 'SIMPLE ENGLISH (ASD-STE100) MODE ACTIVE. Level: %s.\n' "$mode"
  printf 'This mode is enforced by a hook on every prompt. It stays active until the user types "/ste off".\n'
  if [ "$mode" = "strict" ]; then
    printf 'STRICT: a linter checks each reply. If the reply fails, you must rewrite it before you stop.\n'
  fi
  printf 'Toggle: /ste on | /ste strict | /ste off | /ste status\n\n'
  ste_rules_text
} | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'
exit 0
