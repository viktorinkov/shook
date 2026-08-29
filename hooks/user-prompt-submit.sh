#!/usr/bin/env bash
# UserPromptSubmit hook (userPromptSubmitted on Copilot CLI, PreInvocation on Antigravity CLI):
#   1. Handle "/ste on|strict|off|status" and update the flag file.
#   2. Handle "/ste config", "/ste set", "/ste unset", the "project" forms, and "/ste uninstall".
#   3. When the mode is on, add a short reminder to every prompt.
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

usage_set="usage: $cmd set <key> <value> | $cmd unset <key> | $cmd project set <key> <value> | $cmd project unset <key>. Keys: min-words (integer >= 1), min-total (integer >= 1), max-per-100w (number >= 0), lint-type (descriptive | procedural)."

# apply_setting <file> <scope> <set|unset> <cli-key> <value>
# Sets "saved" on success and "note" on failure. Never writes an invalid value.
apply_setting() {
  local f="$1" scope="$2" op="$3" k="$4" v="$5" key
  if [ -z "$f" ]; then
    note="STE: no project directory. Use $cmd set <key> <value> for the global file."
    return
  fi
  if ! key="$(ste_setting_key "$k")"; then
    note="STE: unknown key \"$k\". $usage_set"
    return
  fi
  if [ "$op" = "set" ]; then
    if ! ste_setting_valid "$key" "$v"; then
      note="STE: invalid value \"$v\" for $k. $usage_set"
      return
    fi
    if ste_write_setting "$f" "$key" "$v"; then
      saved="STE SETTING SAVED: $k = $v ($scope file: $f)"
    else
      note="STE: cannot write $f"
    fi
  else
    if ste_write_setting "$f" "$key" ""; then
      saved="STE SETTING REMOVED: $k ($scope file: $f)"
    else
      note="STE: cannot write $f"
    fi
  fi
}

# The plugin uninstall command for the detected harness. See docs/other-harnesses.md.
ste_uninstall_plugin_cmd() {
  case "$STE_HARNESS_NAME" in
    codex)       printf 'codex plugin remove simple-english-hook@simple-english-hook' ;;
    copilot)     printf 'copilot plugin uninstall simple-english-hook' ;;
    antigravity) printf 'agy plugin uninstall simple-english-hook' ;;
    *)           printf 'claude plugin uninstall simple-english-hook@simple-english-hook' ;;
  esac
}

# Best-effort cleanup of everything the hook set wrote. Prints one line per action.
# Idempotent: a second run finds nothing and prints only the final commands.
ste_uninstall() {
  local scmd f tmp p
  # 1. The status line badge.
  scmd="$(jq -r '.statusLine.command // ""' "$STE_CLAUDE_DIR/settings.json" 2>/dev/null)"
  f="$(printf '%s' "$scmd" | sed -E 's/^(bash|sh) +//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')"
  if [ -n "$f" ] && [ -f "$f" ] && grep -q '# simple-english-hook' "$f"; then
    tmp="$(mktemp)"
    grep -v '# simple-english-hook' "$f" > "$tmp" || true
    if [ "$f" = "$STE_CLAUDE_DIR/statusline.sh" ] && \
       printf '#!/usr/bin/env bash\ninput=$(cat)\nprintf "%%s" "$(printf "%%s" "$input" | jq -r .model.display_name)"\n' | cmp -s - "$tmp"; then
      # statusline-install.sh created this file. Delete it and drop the setting.
      rm -f "$tmp" "$f"
      printf 'deleted %s\n' "$f"
      if [ -f "$STE_CLAUDE_DIR/settings.json" ]; then
        cp "$STE_CLAUDE_DIR/settings.json" "$STE_CLAUDE_DIR/settings.json.bak" 2>/dev/null
        tmp="$(mktemp)"
        if jq 'del(.statusLine)' "$STE_CLAUDE_DIR/settings.json" > "$tmp" 2>/dev/null; then
          mv "$tmp" "$STE_CLAUDE_DIR/settings.json"
          printf 'removed statusLine from %s (backup: settings.json.bak)\n' "$STE_CLAUDE_DIR/settings.json"
        else
          rm -f "$tmp"
        fi
      fi
    else
      # A user script. Remove only the badge line. Keep the file mode.
      cat "$tmp" > "$f" && rm -f "$tmp"
      printf 'removed the badge line from %s\n' "$f"
    fi
  fi
  if [ -n "$f" ] && [ -f "$f.bak" ]; then
    rm -f "$f.bak"
    printf 'deleted %s.bak\n' "$f"
  fi
  # 2. Global state: badge scripts, mode flag, score, config file.
  for p in "$STE_CLAUDE_DIR/simple-english-hook" "$STE_FLAG" "$STE_SCORE" "$(ste_config_file)"; do
    [ -e "$p" ] || continue
    rm -rf "$p"
    printf 'deleted %s\n' "$p"
  done
  # 3. The current project.
  if [ -n "${STE_PROJECT_DIR:-}" ]; then
    for p in "$STE_PROJECT_DIR/.claude/ste-mode" "$STE_PROJECT_DIR/.claude/ste-config.json"; do
      [ -f "$p" ] || continue
      rm -f "$p"
      printf 'deleted %s\n' "$p"
    done
    rmdir "$STE_PROJECT_DIR/.claude" 2>/dev/null && printf 'removed empty %s\n' "$STE_PROJECT_DIR/.claude"
  fi
  # 4. A hook cannot uninstall the plugin that runs it. The user runs this part.
  printf 'Run this command yourself, because a hook cannot uninstall the plugin that runs it: %s\n' "$(ste_uninstall_plugin_cmd)"
  printf 'Repos other than this one: delete .claude/ste-mode and .claude/ste-config.json by hand.\n'
}

# Accepted forms: /ste, $ste (Codex skill mention), @ste, and /<plugin>:ste (Copilot CLI).
if printf '%s' "$first" | grep -Eq '^[/$@]([a-z0-9-]+:)?ste( |$)'; then
    arg="$(printf '%s' "$first" | awk '{print $2}')"
    arg2="$(printf '%s' "$first" | awk '{print $3}')"
    arg3="$(printf '%s' "$first" | awk '{print $4}')"
    arg4="$(printf '%s' "$first" | awk '{print $5}')"
    note=""; saved=""; is_config=""
    case "$arg" in
      on|strict|off) ste_set_mode "$arg" ;;
      set|unset) is_config=1; apply_setting "$(ste_config_file)" global "$arg" "$arg2" "$arg3" ;;
      config) is_config=1 ;;
      uninstall)
        text="$(
          ste_uninstall
          printf 'Reply with the lines above and nothing else. Do not run tools.\n'
        )"
        ste_emit UserPromptSubmit "$text" "STE uninstalled"
        exit 0 ;;
      project)
        case "$arg2" in
          on|strict|off|clear) ste_set_project_mode "$arg2" ;;
          set|unset) is_config=1; apply_setting "$(ste_project_config_file)" project "$arg2" "$arg3" "$arg4" ;;
          *) note="STE: usage: $cmd project on | strict | off | clear | set <key> <value> | unset <key>" ;;
        esac ;;
      status|"") ;;
      *) note="STE: unknown option \"$arg\". Use: $cmd on | strict | off | status | config | set | unset | uninstall | project <mode>" ;;
    esac
    if [ -n "$is_config" ]; then
      if [ -n "$note" ]; then
        text="$(printf '%s\nReply with one short line that repeats this message. Do not do other work.' "$note")"
      else
        text="$(
          [ -n "$saved" ] && printf '%s\n' "$saved"
          ste_config_table
          printf 'Commands: %s config | %s set <key> <value> | %s unset <key> | %s project set <key> <value> | %s project unset <key>\n' "$cmd" "$cmd" "$cmd" "$cmd" "$cmd"
          if [ -n "$saved" ]; then
            printf 'Reply with one short line that confirms the key, the value, and the file, then the STE CONFIG table above in a code block. Do not do other work.\n'
          else
            printf 'Reply with the STE CONFIG table above in a code block. Do not do other work.\n'
          fi
        )"
      fi
      ste_emit UserPromptSubmit "$text" "STE config"
      exit 0
    fi
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
