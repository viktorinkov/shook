#!/usr/bin/env bash
# Shared helpers for the Simple English (STE) hook set.
# Source this file. Do not run it.

STE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STE_CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STE_FLAG="$STE_CLAUDE_DIR/.simple-english-active"

# Valid modes: off | on | strict
#   off    - hooks are silent
#   on     - inject the rules at session start and a reminder on every prompt
#   strict - "on" plus a lint gate on every reply (Stop hook)
#
# Resolution order:
#   1. STE_MODE environment variable (also settable per repo in .claude/settings.json "env")
#   2. <project>/.claude/ste-mode   (per-repo file, safe to commit)
#   3. $CLAUDE_CONFIG_DIR/.simple-english-active   (global flag, written by /ste)
#   4. off
STE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
STE_PROJECT_FLAG="$STE_PROJECT_DIR/.claude/ste-mode"

ste_read_flag() {
  local m
  m="$(head -n1 "$1" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  case "$m" in on|strict|off) printf '%s' "$m" ;; *) printf '' ;; esac
}

ste_mode() {
  local m
  if [ -n "${STE_MODE:-}" ]; then
    m="$(printf '%s' "$STE_MODE" | tr '[:upper:]' '[:lower:]')"
    case "$m" in on|strict) printf '%s' "$m" ;; *) printf 'off' ;; esac
    return
  fi
  if [ -f "$STE_PROJECT_FLAG" ]; then
    m="$(ste_read_flag "$STE_PROJECT_FLAG")"
    [ -n "$m" ] && { printf '%s' "$m"; return; }
  fi
  if [ -f "$STE_FLAG" ]; then
    m="$(ste_read_flag "$STE_FLAG")"
    [ -n "$m" ] && { printf '%s' "$m"; return; }
  fi
  printf 'off'
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

# Locate a file inside the installed simple-english plugin (AminBlg/SimpleEnglish).
# The plugin is a prerequisite. install.sh installs it. Prints nothing when missing.
ste_plugin_file() {
  local rel="$1" f
  for f in \
    "$STE_CLAUDE_DIR"/plugins/cache/simple-english/simple-english/*/"$rel" \
    "$STE_CLAUDE_DIR/plugins/marketplaces/simple-english/$rel"; do
    [ -f "$f" ] && { printf '%s' "$f"; return; }
  done
  return 1
}

STE_PLUGIN_MISSING_NOTE='SIMPLE ENGLISH HOOK: the simple-english plugin is not installed, so the rule text is unavailable. Tell the user to run install.sh from the simple-english-hook repo, or: claude plugin marketplace add AminBlg/SimpleEnglish && claude plugin install simple-english@simple-english'

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
