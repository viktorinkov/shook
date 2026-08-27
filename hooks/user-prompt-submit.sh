#!/usr/bin/env bash
# UserPromptSubmit hook:
#   1. Handle "/ste on|strict|off|status" and update the flag file.
#   2. When the mode is on, add a short reminder to every prompt.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

input="$(cat)"
prompt="$(printf '%s' "$input" | jq -r '.prompt // ""' 2>/dev/null | tr -d '\r')"
first="$(printf '%s' "$prompt" | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"

case "$first" in
  /ste|/ste:ste|/ste\ *|/ste:ste\ *)
    arg="$(printf '%s' "$first" | awk '{print $2}')"
    arg2="$(printf '%s' "$first" | awk '{print $3}')"
    case "$arg" in
      on|strict|off) ste_set_mode "$arg" ;;
      project)
        case "$arg2" in
          on|strict|off|clear) ste_set_project_mode "$arg2" ;;
          *) printf 'STE: usage: /ste project on | strict | off | clear\n' ;;
        esac ;;
      status|"") ;;
      *) printf 'STE: unknown option "%s". Use: /ste on | strict | off | status | project <mode>\n' "$arg" ;;
    esac
    mode="$(ste_mode)"
    printf 'STE MODE IS NOW: %s (source: %s, project file: %s). Reply with one short line that confirms the mode and its source. Do not do other work.\n' "$mode" "$(ste_mode_source)" "$STE_PROJECT_FLAG"
    if [ "$mode" != "off" ] && [ "$arg" != "status" ] && [ -n "$arg" ]; then
      printf '\nThe rules below apply from this reply on.\n\n'
      ste_rules_text
    fi
    exit 0
    ;;
esac

mode="$(ste_mode)"
[ "$mode" = "off" ] && exit 0

cat "$STE_DIR/rules/reminder.md"
if [ "$mode" = "strict" ]; then
  printf 'STRICT: a linter reads your reply. Replies with violations are sent back for a rewrite.\n'
fi
exit 0
