#!/usr/bin/env bash
# Cursor hook dispatcher. Cursor runs one command per event; this script reads
# hook_event_name from the stdin JSON and routes to the shared hook scripts.
# Wired by cursor-install.sh through .cursor/hooks.json (project or user level).
# Events (https://cursor.com/docs/hooks):
#   sessionStart       -> session-start.sh   {"additional_context": ...}
#   beforeSubmitPrompt -> user-prompt-submit.sh  {"continue": ..., "user_message": ...}
#   afterAgentResponse -> save the reply text for the stop hook (strict mode only)
#   stop               -> stop-gate.sh       {"followup_message": ...} on a failed lint
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export STE_HARNESS=cursor

input="$(cat 2>/dev/null)"
event="$(printf '%s' "$input" | jq -r '.hook_event_name // ""' 2>/dev/null)"

case "$event" in
  sessionStart)
    printf '%s' "$input" | bash "$DIR/session-start.sh"
    ;;
  beforeSubmitPrompt)
    out="$(printf '%s' "$input" | bash "$DIR/user-prompt-submit.sh")"
    # An empty answer means "mode off". Cursor still gets a valid allow decision.
    if [ -n "$out" ]; then printf '%s\n' "$out"; else printf '{"continue":true}\n'; fi
    ;;
  afterAgentResponse)
    source "$DIR/common.sh"
    ste_project_from_input "$input"
    [ "$(ste_mode)" = "strict" ] || exit 0
    ste_cursor_save_reply "$input"
    ;;
  stop)
    printf '%s' "$input" | bash "$DIR/stop-gate.sh"
    ;;
esac
exit 0
