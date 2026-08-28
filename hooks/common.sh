#!/usr/bin/env bash
# Shared helpers for the Simple English (STE) hook set.
# Source this file. Do not run it.

STE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STE_CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Harness detection. The same scripts run under four harnesses.
#   claude  - Claude Code (default)
#   codex   - OpenAI Codex CLI. Sets PLUGIN_DATA (and CLAUDE_PLUGIN_ROOT for compatibility).
#   copilot - GitHub Copilot CLI. Sets COPILOT_PLUGIN_DATA.
#   gemini  - Gemini CLI. Sets GEMINI_SESSION_ID, GEMINI_CWD and CLAUDE_PROJECT_DIR.
# Override with STE_HARNESS=<name>. See docs/other-harnesses.md.
ste_harness() {
  if [ -n "${STE_HARNESS:-}" ]; then printf '%s' "$STE_HARNESS"
  elif [ -n "${COPILOT_PLUGIN_DATA:-}" ]; then printf 'copilot'
  elif [ -n "${GEMINI_SESSION_ID:-}" ]; then printf 'gemini'
  elif [ -n "${PLUGIN_DATA:-}" ]; then printf 'codex'
  else printf 'claude'
  fi
}
STE_HARNESS_NAME="$(ste_harness)"

# Where the global mode flag lives. Codex and Copilot give each plugin a writable
# data directory. Gemini has none, so the flag goes next to its settings.
case "$STE_HARNESS_NAME" in
  codex)   STE_STATE_DIR="${PLUGIN_DATA:-$STE_CLAUDE_DIR}" ;;
  copilot) STE_STATE_DIR="${COPILOT_PLUGIN_DATA:-$STE_CLAUDE_DIR}" ;;
  gemini)  STE_STATE_DIR="${GEMINI_CLI_HOME:-$HOME}/.gemini" ;;
  *)       STE_STATE_DIR="$STE_CLAUDE_DIR" ;;
esac
STE_FLAG="$STE_STATE_DIR/.simple-english-active"
STE_SCORE="$STE_STATE_DIR/.simple-english-score"   # last lint result, written by the Stop hook

# Valid modes: off | on | strict
#   off    - hooks are silent
#   on     - inject the rules at session start and a reminder on every prompt
#   strict - "on" plus a lint gate on every reply (Stop hook)
#
# Resolution order:
#   1. STE_MODE environment variable (also settable per repo in .claude/settings.json "env")
#   2. <project>/.claude/ste-mode   (per-repo file, safe to commit)
#   3. $STE_STATE_DIR/.simple-english-active   (global flag, written by /ste)
#   4. off
STE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
STE_PROJECT_FLAG="$STE_PROJECT_DIR/.claude/ste-mode"

# Every harness sends the project directory as "cwd" in the hook input JSON.
# Claude Code and Gemini also set CLAUDE_PROJECT_DIR. Codex and Copilot do not.
# When the variable is unset, take the directory from the input.
ste_project_from_input() {
  local d
  [ -n "${CLAUDE_PROJECT_DIR:-}" ] && return 0
  d="$(printf '%s' "$1" | jq -r '.cwd // ""' 2>/dev/null)"
  [ -n "$d" ] && [ -d "$d" ] || return 0
  STE_PROJECT_DIR="$d"
  STE_PROJECT_FLAG="$d/.claude/ste-mode"
}

ste_read_flag() {
  local m
  m="$(head -n1 "$1" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  case "$m" in on|strict|off) printf '%s' "$m" ;; *) printf '' ;; esac
}

ste_mode() {
  local m=""
  if [ -n "${STE_MODE:-}" ]; then
    m="$(printf '%s' "$STE_MODE" | tr '[:upper:]' '[:lower:]')"
    case "$m" in on|strict) ;; *) m="off" ;; esac
  fi
  [ -z "$m" ] && [ -f "$STE_PROJECT_FLAG" ] && m="$(ste_read_flag "$STE_PROJECT_FLAG")"
  [ -z "$m" ] && [ -f "$STE_FLAG" ] && m="$(ste_read_flag "$STE_FLAG")"
  [ -z "$m" ] && m="off"
  # Copilot CLI's stop event has no reply text, so the lint gate cannot run there.
  [ "$m" = "strict" ] && [ "$STE_HARNESS_NAME" = "copilot" ] && m="on"
  printf '%s' "$m"
}

# Where the active mode comes from: env | project | global | default
ste_mode_source() {
  [ -n "${STE_MODE:-}" ] && { printf 'env'; return; }
  [ -f "$STE_PROJECT_FLAG" ] && [ -n "$(ste_read_flag "$STE_PROJECT_FLAG")" ] && { printf 'project'; return; }
  [ -f "$STE_FLAG" ] && [ -n "$(ste_read_flag "$STE_FLAG")" ] && { printf 'global'; return; }
  printf 'default'
}

ste_set_mode() {
  case "$1" in
    off) rm -f "$STE_FLAG" ;;
    on|strict) mkdir -p "$(dirname "$STE_FLAG")"; printf '%s\n' "$1" > "$STE_FLAG" ;;
  esac
}

# Per-repo mode. "off" is written as a file, so a repo can opt out of a global "on".
# "clear" removes the file.
ste_set_project_mode() {
  case "$1" in
    clear) rm -f "$STE_PROJECT_FLAG" ;;
    on|strict|off) mkdir -p "$(dirname "$STE_PROJECT_FLAG")"; printf '%s\n' "$1" > "$STE_PROJECT_FLAG" ;;
  esac
}

# The toggle command as the user types it in this harness.
ste_cmd() {
  case "$STE_HARNESS_NAME" in
    codex)   printf '$ste' ;;
    copilot) printf '/simple-english-hook:ste' ;;
    *)       printf '/ste' ;;
  esac
}

# Print hook output in the format the harness expects.
#   ste_emit <SessionStart|UserPromptSubmit> <context text> [status message]
# claude:  SessionStart wants JSON; UserPromptSubmit takes plain text.
# codex:   JSON with hookSpecificOutput; systemMessage shows in the UI (a badge substitute).
# gemini:  same JSON; the prompt event is called BeforeAgent.
# copilot: {"additionalContext": ...} on sessionStart only. Prompt hook output is dropped.
ste_emit() {
  local event="$1" text="$2" sys="${3:-}"
  case "$STE_HARNESS_NAME" in
    codex)
      printf '%s' "$text" | jq -Rs --arg e "$event" --arg s "$sys" \
        '{hookSpecificOutput:{hookEventName:$e,additionalContext:.}} + (if $s == "" then {} else {systemMessage:$s} end)' ;;
    gemini)
      [ "$event" = "UserPromptSubmit" ] && event="BeforeAgent"
      printf '%s' "$text" | jq -Rs --arg e "$event" --arg s "$sys" \
        '{hookSpecificOutput:{hookEventName:$e,additionalContext:.}} + (if $s == "" then {} else {systemMessage:$s} end)' ;;
    copilot)
      [ "$event" = "SessionStart" ] && printf '%s' "$text" | jq -Rs '{additionalContext:.}' ;;
    *)
      if [ "$event" = "SessionStart" ]; then
        printf '%s' "$text" | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'
      else
        printf '%s\n' "$text"
      fi ;;
  esac
}

# Locate a file inside the installed simple-english plugin (AminBlg/SimpleEnglish).
# The plugin is a prerequisite. install.sh installs it. Prints nothing when missing.
# STE_PLUGIN_DIR points at a clone of the plugin repo. Other harnesses need it.
ste_plugin_file() {
  local rel="$1" f
  if [ -n "${STE_PLUGIN_DIR:-}" ] && [ -f "$STE_PLUGIN_DIR/$rel" ]; then
    printf '%s' "$STE_PLUGIN_DIR/$rel"; return
  fi
  for f in \
    "$STE_CLAUDE_DIR"/plugins/cache/simple-english/simple-english/*/"$rel" \
    "$STE_CLAUDE_DIR/plugins/marketplaces/simple-english/$rel"; do
    [ -f "$f" ] && { printf '%s' "$f"; return; }
  done
  return 1
}

STE_PLUGIN_MISSING_NOTE='SIMPLE ENGLISH HOOK: the simple-english plugin is not installed, so the rule text is unavailable. Tell the user to run install.sh from the simple-english-hook repo, or: claude plugin marketplace add AminBlg/SimpleEnglish && claude plugin install simple-english@simple-english. On Codex, Copilot CLI or Gemini CLI: git clone https://github.com/AminBlg/SimpleEnglish and set STE_PLUGIN_DIR to the clone.'

# Full rule set (the plugin output style, frontmatter removed).
ste_rules_text() {
  local f
  if f="$(ste_plugin_file output-styles/simple-english.md)"; then
    awk 'NR==1 && $0=="---" {fm=1; next} fm && $0=="---" {fm=0; next} !fm' "$f" | sed '/./,$!d'
  else
    printf '%s\n' "$STE_PLUGIN_MISSING_NOTE"
  fi
}

ste_lint_script() {
  ste_plugin_file evals/ste_lint.py
}

# True when the user's status line script contains the badge marker.
ste_badge_installed() {
  local cmd f
  cmd="$(jq -r '.statusLine.command // ""' "$STE_CLAUDE_DIR/settings.json" 2>/dev/null)"
  f="$(printf '%s' "$cmd" | sed -E 's/^(bash|sh) +//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')"
  [ -n "$f" ] && [ -f "$f" ] && grep -q "simple-english-hook" "$f"
}
