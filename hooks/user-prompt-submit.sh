#!/usr/bin/env bash
# UserPromptSubmit hook (userPromptSubmitted on Copilot CLI, PreInvocation on Antigravity CLI):
#   1. Handle "/ste on|strict|off|status" and update the flag file.
#   2. When the mode is on, add a short reminder to every prompt.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

input="$(cat)"
ste_project_from_input "$input"
prompt="$(printf '%s' "$input" | jq -r '.prompt // ""' 2>/dev/null | tr -d '\r')"
# Antigravity sends no prompt. Read the newest user message from the transcript,
# but only on the first model call of the turn. Later calls get the reminder only.
if [ -z "$prompt" ] && [ "$STE_HARNESS_NAME" = "antigravity" ] && ste_transcript_turn_start "$input"; then
  prompt="$(ste_transcript_prompt "$input" | tr -d '\r')"
fi
first="$(printf '%s' "$prompt" | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
cmd="$(ste_cmd)"

# Accepted forms: /ste, $ste (Codex skill mention), @ste, and /<plugin>:ste (Copilot CLI).
if printf '%s' "$first" | grep -Eq '^[/$@]([a-z0-9-]+:)?ste( |$)'; then
    arg="$(printf '%s' "$first" | awk '{print $2}')"
    arg2="$(printf '%s' "$first" | awk '{print $3}')"
    note=""
    case "$arg" in
      on|strict|off) ste_set_mode "$arg" ;;
      project)
        case "$arg2" in
          on|strict|off|clear) ste_set_project_mode "$arg2" ;;
          *) note="STE: usage: $cmd project on | strict | off | clear" ;;
        esac ;;
      status|"") ;;
      *) note="STE: unknown option \"$arg\". Use: $cmd on | strict | off | status | project <mode>" ;;
    esac
    mode="$(ste_mode)"
    text="$(
      [ -n "$note" ] && printf '%s\n' "$note"
      printf 'STE MODE IS NOW: %s (source: %s, project file: %s). Reply with one short line that confirms the mode and its source. Do not do other work.\n' "$mode" "$(ste_mode_source)" "${STE_PROJECT_FLAG:-none}"
      if [ "$mode" != "off" ] && [ "$arg" != "status" ] && [ -n "$arg" ]; then
        printf '\nThe rules below apply from this reply on.\n\n'
        ste_rules_text
      fi
    )"
    ste_emit UserPromptSubmit "$text" "STE mode: $mode"
    exit 0
fi

mode="$(ste_mode)"
[ "$mode" = "off" ] && exit 0

text="$(
  cat "$STE_DIR/rules/reminder.md"
  if [ "$mode" = "strict" ]; then
    printf 'STRICT: a linter reads your reply. Replies with violations are sent back for a rewrite.\n'
  fi
)"
ste_emit UserPromptSubmit "$text"
exit 0
