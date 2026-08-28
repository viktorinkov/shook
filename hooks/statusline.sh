#!/usr/bin/env bash
# Prints a colored [STE] badge when the mode is on. Prints nothing when off.
# Reads the status line JSON on stdin to find the project directory.
input="$(cat 2>/dev/null)"
if [ -n "$input" ] && command -v jq >/dev/null; then
  d="$(printf '%s' "$input" | jq -r '.workspace.project_dir // .cwd // ""' 2>/dev/null)"
  [ -n "$d" ] && export CLAUDE_PROJECT_DIR="$d"
fi
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
case "$(ste_mode)" in
  on)     printf '\033[38;5;75m[STE]\033[0m' ;;
  strict)
    score=""
    [ -f "$STE_SCORE" ] && score="$(awk '{printf " %.1f", $1}' "$STE_SCORE" 2>/dev/null)"
    printf '\033[38;5;203m[STE:STRICT%s]\033[0m' "$score" ;;
esac
