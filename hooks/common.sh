#!/usr/bin/env bash
# Shared helpers for the Simple English (STE) hook set.
# Source this file. Do not run it.

STE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STE_CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Harness detection. The same scripts run under five harnesses.
#   claude      - Claude Code (default)
#   codex       - OpenAI Codex CLI. Sets PLUGIN_ROOT and PLUGIN_DATA, plus CLAUDE_PLUGIN_ROOT and
#                 CLAUDE_PLUGIN_DATA as aliases. Verified with Codex CLI 0.149.0.
#   copilot     - GitHub Copilot CLI. Sets COPILOT_PLUGIN_DATA.
#   antigravity - Antigravity CLI (agy). Sets ANTIGRAVITY_CONVERSATION_ID. The root
#                 hooks.json also sets STE_HARNESS=antigravity, so a nested Claude Code
#                 session inside an agy terminal is not misdetected.
# Override with STE_HARNESS=<name>. See docs/other-harnesses.md.
#   cursor      - Cursor (the IDE). hooks/cursor.sh sets STE_HARNESS=cursor. Fallback: Cursor
#                 gives hook processes CURSOR_VERSION, and it never sets CLAUDE_PLUGIN_ROOT.
ste_harness() {
  if [ -n "${STE_HARNESS:-}" ]; then printf '%s' "$STE_HARNESS"
  elif [ -n "${COPILOT_PLUGIN_DATA:-}" ]; then printf 'copilot'
  elif [ -n "${PLUGIN_DATA:-}" ]; then printf 'codex'
  elif [ -n "${ANTIGRAVITY_CONVERSATION_ID:-}" ]; then printf 'antigravity'
  elif [ -n "${CURSOR_VERSION:-}" ] && [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then printf 'cursor'  # cursor block
  else printf 'claude'
  fi
}
STE_HARNESS_NAME="$(ste_harness)"

# Where the global mode flag lives. Codex and Copilot give each plugin a writable
# data directory. Antigravity has none, so the flag goes into its shared config
# directory (~/.gemini/config, the same place that holds its installed plugins).
case "$STE_HARNESS_NAME" in
  codex)       STE_STATE_DIR="${PLUGIN_DATA:-$STE_CLAUDE_DIR}" ;;
  copilot)     STE_STATE_DIR="${COPILOT_PLUGIN_DATA:-$STE_CLAUDE_DIR}" ;;
  antigravity) STE_STATE_DIR="$HOME/.gemini/config" ;;
  cursor)      STE_STATE_DIR="$HOME/.cursor" ;;  # cursor block
  *)           STE_STATE_DIR="$STE_CLAUDE_DIR" ;;
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
# Antigravity runs hooks inside the installed plugin copy, not in the project.
# That copy holds this repo's own .claude/ste-mode, so PWD is not a project there.
[ "$STE_HARNESS_NAME" = "antigravity" ] && [ -z "${CLAUDE_PROJECT_DIR:-}" ] && STE_PROJECT_DIR=""
STE_PROJECT_FLAG="${STE_PROJECT_DIR:+$STE_PROJECT_DIR/.claude/ste-mode}"

# Claude Code, Codex and Copilot send the project directory as "cwd" in the hook
# input JSON. Antigravity sends "workspacePaths" (empty outside a project).
# Claude Code also sets CLAUDE_PROJECT_DIR. When the variable is unset, take the
# directory from the input.
ste_project_from_input() {
  local d
  [ -n "${CLAUDE_PROJECT_DIR:-}" ] && return 0
  d="$(printf '%s' "$1" | jq -r '.cwd // .workspacePaths[0]? // ""' 2>/dev/null)"
  [ -n "$d" ] && [ -d "$d" ] || return 0
  STE_PROJECT_DIR="$d"
  STE_PROJECT_FLAG="$d/.claude/ste-mode"
}

# Antigravity sends no prompt and no reply text to its hooks. Both live in the
# transcript file named by "transcriptPath": one JSON object per line with
# step_index, source (USER_EXPLICIT | SYSTEM | SYSTEM_SDK | MODEL), type
# (USER_INPUT | EPHEMERAL_MESSAGE | SYSTEM_MESSAGE | PLANNER_RESPONSE ...) and content.
ste_transcript_path() {
  local tp
  tp="$(printf '%s' "$1" | jq -r '.transcriptPath // .transcript_path // ""' 2>/dev/null)"
  [ -n "$tp" ] && [ -f "$tp" ] || return 1
  printf '%s' "$tp"
}

# The newest user message. The transcript wraps it in <USER_REQUEST> tags and
# adds metadata blocks after it. Print only the text inside the tags.
ste_transcript_prompt() {
  local tp raw
  tp="$(ste_transcript_path "$1")" || return 0
  raw="$(jq -rs '[.[] | select(.type == "USER_INPUT")] | last | .content // ""' "$tp" 2>/dev/null)"
  if printf '%s' "$raw" | grep -q '^<USER_REQUEST>$'; then
    printf '%s' "$raw" | awk '/^<USER_REQUEST>$/ {f=1; next} /^<\/USER_REQUEST>$/ {f=0} f'
  else
    printf '%s' "$raw"
  fi
}

# True when the newest user message has no model step after it, so this is the
# first model call of the turn. PreInvocation also fires after tool calls and
# after a Stop hook continued the turn. The toggle must run once per prompt.
ste_transcript_turn_start() {
  local tp
  tp="$(ste_transcript_path "$1")" || return 0
  jq -es '([.[] | select(.type == "USER_INPUT")] | last | .step_index // -1)
          >= ([.[] | select(.source == "MODEL")] | last | .step_index // -1)' "$tp" >/dev/null 2>&1
}

# The last reply of the current turn: the newest MODEL text step after the newest user message.
ste_transcript_reply() {
  local tp
  tp="$(ste_transcript_path "$1")" || return 0
  jq -rs '([.[] | select(.type == "USER_INPUT")] | last | .step_index // -1) as $u
          | [.[] | select(.source == "MODEL" and .type == "PLANNER_RESPONSE" and .step_index > $u)]
          | last | .content // ""' "$tp" 2>/dev/null
}

# True when a Stop hook already sent the current turn back with the given marker text.
ste_transcript_has_block() {
  local tp
  tp="$(ste_transcript_path "$1")" || return 1
  jq -es --arg m "$2" '([.[] | select(.type == "USER_INPUT")] | last | .step_index // -1) as $u
          | [.[] | select(.type == "SYSTEM_MESSAGE" and .step_index > $u and (.content | contains($m)))]
          | length > 0' "$tp" >/dev/null 2>&1
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

# --- settings ---
# Strict-mode gate settings. Keys are snake_case in the files and kebab-case on
# the command line (min-words, min-total, max-per-100w, lint-type).
#   min_words     integer >= 1              default 40           shorter replies skip the gate
#   min_total     integer >= 1              default 2            fewer violations skip the gate
#   max_per_100w  number >= 0               default 1.0          block above this density
#   lint_type     descriptive | procedural  default descriptive  linter profile
#
# Resolution order for each key, first hit wins:
#   1. environment variable: STE_MIN_WORDS, STE_MIN_TOTAL, STE_MAX_PER_100W, STE_LINT_TYPE
#   2. <project>/.claude/ste-config.json          written by "/ste project set"
#   3. $STE_STATE_DIR/simple-english-hook.json    written by "/ste set"
#   4. the default
STE_SETTING_KEYS="min_words min_total max_per_100w lint_type"

ste_config_file() { printf '%s' "$STE_STATE_DIR/simple-english-hook.json"; }
# The project file follows STE_PROJECT_DIR, which ste_project_from_input can change.
ste_project_config_file() { printf '%s' "${STE_PROJECT_DIR:+$STE_PROJECT_DIR/.claude/ste-config.json}"; }

ste_setting_default() {
  case "$1" in
    min_words)    printf '40' ;;
    min_total)    printf '2' ;;
    max_per_100w) printf '1.0' ;;
    lint_type)    printf 'descriptive' ;;
  esac
}

# min_words -> STE_MIN_WORDS
ste_setting_env() { printf 'STE_%s' "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"; }
# min_words -> min-words
ste_setting_cli() { printf '%s' "$1" | tr '_' '-'; }
# min-words -> min_words. Fails on an unknown key.
ste_setting_key() {
  local k
  k="$(printf '%s' "$1" | tr '-' '_')"
  case " $STE_SETTING_KEYS " in *" $k "*) printf '%s' "$k" ;; *) return 1 ;; esac
}

# True when the value is valid for the key.
ste_setting_valid() {
  case "$1" in
    min_words|min_total) printf '%s' "$2" | grep -Eq '^[1-9][0-9]*$' ;;
    max_per_100w)        printf '%s' "$2" | grep -Eq '^([0-9]+\.?[0-9]*|\.[0-9]+)$' ;;
    lint_type)           case "$2" in descriptive|procedural) return 0 ;; *) return 1 ;; esac ;;
    *) return 1 ;;
  esac
}

# One key from one config file. Prints nothing when the file, the key, or a valid value is missing.
ste_setting_from_file() {
  local f="$1" key="$2" v
  [ -n "$f" ] && [ -f "$f" ] || return 0
  v="$(jq -r --arg k "$key" '.[$k] // "" | tostring' "$f" 2>/dev/null)"
  ste_setting_valid "$key" "$v" && printf '%s' "$v"
  return 0
}

# Where the active value comes from: env | project | global | default
ste_setting_source() {
  local key="$1" name
  name="$(ste_setting_env "$key")"
  [ -n "${!name:-}" ] && ste_setting_valid "$key" "${!name}" && { printf 'env'; return; }
  [ -n "$(ste_setting_from_file "$(ste_project_config_file)" "$key")" ] && { printf 'project'; return; }
  [ -n "$(ste_setting_from_file "$(ste_config_file)" "$key")" ] && { printf 'global'; return; }
  printf 'default'
}

# The active value of one key.
ste_setting() {
  local key="$1" name
  case "$(ste_setting_source "$key")" in
    env)     name="$(ste_setting_env "$key")"; printf '%s' "${!name}" ;;
    project) ste_setting_from_file "$(ste_project_config_file)" "$key" ;;
    global)  ste_setting_from_file "$(ste_config_file)" "$key" ;;
    *)       ste_setting_default "$key" ;;
  esac
}

# ste_write_setting <file> <snake_key> <value>   An empty value removes the key.
# Writes a JSON object with jq. Numbers stay numbers. Atomic: temp file, then mv.
ste_write_setting() {
  local f="$1" key="$2" v="$3" cur tmp
  [ -n "$f" ] || return 1
  mkdir -p "$(dirname "$f")" || return 1
  cur="$( [ -f "$f" ] && jq -c 'if type == "object" then . else {} end' "$f" 2>/dev/null )"
  [ -n "$cur" ] || cur='{}'
  tmp="$(mktemp "$(dirname "$f")/.ste-config.XXXXXX")" || return 1
  if printf '%s' "$cur" | jq --arg k "$key" --arg v "$v" \
       'if $v == "" then del(.[$k]) else .[$k] = (if $k == "lint_type" then $v else ($v | tonumber) end) end' \
       > "$tmp" 2>/dev/null; then
    mv "$tmp" "$f"
  else
    rm -f "$tmp"; return 1
  fi
}

# The table that "/ste config" prints. One line per key: value, source, env name.
ste_config_table() {
  local key f
  printf 'STE CONFIG (mode: %s, source: %s):\n' "$(ste_mode)" "$(ste_mode_source)"
  printf '  %-13s %-12s %-8s %s\n' key value source env
  for key in $STE_SETTING_KEYS; do
    printf '  %-13s %-12s %-8s %s\n' "$(ste_setting_cli "$key")" "$(ste_setting "$key")" \
      "$(ste_setting_source "$key")" "$(ste_setting_env "$key")"
  done
  f="$(ste_config_file)"
  printf '  global file:  %s (%s)\n' "$f" "$([ -f "$f" ] && printf 'present' || printf 'absent')"
  f="$(ste_project_config_file)"
  printf '  project file: %s (%s)\n' "${f:-none}" "$([ -n "$f" ] && [ -f "$f" ] && printf 'present' || printf 'absent')"
}
# --- end settings ---

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
# claude:      SessionStart wants JSON; UserPromptSubmit takes plain text.
# codex:       JSON with hookSpecificOutput; systemMessage shows in the UI (a badge substitute).
# copilot:     {"additionalContext": ...} on sessionStart only. Prompt hook output is dropped.
# antigravity: {"injectSteps": [step]}. SessionStart injects a system message, which
#              stays in the conversation. PreInvocation injects an ephemeral message,
#              which the model sees for the next call only. The status text has no UI.
ste_emit() {
  local event="$1" text="$2" sys="${3:-}"
  case "$STE_HARNESS_NAME" in
    codex)
      printf '%s' "$text" | jq -Rs --arg e "$event" --arg s "$sys" \
        '{hookSpecificOutput:{hookEventName:$e,additionalContext:.}} + (if $s == "" then {} else {systemMessage:$s} end)' ;;
    copilot)
      [ "$event" = "SessionStart" ] && printf '%s' "$text" | jq -Rs '{additionalContext:.}' ;;
    antigravity)
      if [ "$event" = "SessionStart" ]; then
        printf '%s' "$text" | jq -Rs '{injectSteps:[{systemMessage:{systemMessage:.}}]}'
      else
        printf '%s' "$text" | jq -Rs '{injectSteps:[{ephemeralMessage:.}]}'
      fi ;;
    *)
      if [ "$event" = "SessionStart" ]; then
        printf '%s' "$text" | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'
      else
        printf '%s\n' "$text"
      fi ;;
  esac
}

# Send the reply back for a rewrite.
#   ste_emit_block <reason>
# Claude Code and Codex read {"decision":"block"}. Antigravity's Stop event reads
# {"decision":"continue"} and shows the reason to the model as a system message.
ste_emit_block() {
  case "$STE_HARNESS_NAME" in
    antigravity) jq -n --arg r "$1" '{decision:"continue", reason:$r}' ;;
    *)           jq -n --arg r "$1" '{decision:"block", reason:$r}' ;;
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

STE_PLUGIN_MISSING_NOTE='SIMPLE ENGLISH HOOK: the simple-english plugin is not installed, so the rule text is unavailable. Tell the user to install it: claude plugin marketplace add AminBlg/SimpleEnglish && claude plugin install simple-english@simple-english. Outside Claude Code, set STE_PLUGIN_DIR to a clone of https://github.com/AminBlg/SimpleEnglish.'

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

# ---- cursor block (shared default) ------------------------------------------
# True when the harness already loads the rules from an always-on rule file, so
# a hook does not have to inject them again. Overridden in the cursor block below.
ste_rules_preloaded() { return 1; }
# ---- cursor block end --------------------------------------------------------

# True when the user's status line script contains the badge marker.
ste_badge_installed() {
  local cmd f
  cmd="$(jq -r '.statusLine.command // ""' "$STE_CLAUDE_DIR/settings.json" 2>/dev/null)"
  f="$(printf '%s' "$cmd" | sed -E 's/^(bash|sh) +//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')"
  [ -n "$f" ] && [ -f "$f" ] && grep -q "simple-english-hook" "$f"
}

# ==== cursor block start ======================================================
# Cursor (the IDE) support. All Cursor-only code lives between these markers.
# Contract, from https://cursor.com/docs/hooks :
#   sessionStart        out: {"additional_context": "..."}
#   beforeSubmitPrompt  in: {"prompt": ...}; out: {"continue": bool, "user_message": "..."}.
#                       A blocked prompt never reaches the model. No context injection.
#   afterAgentResponse  in: {"text": "..."}; no output. hooks/cursor.sh saves the text.
#   stop                in: {"status", "loop_count"}; out: {"followup_message": "..."}.
# The always-on path is a project rule file, from https://cursor.com/docs/context/rules :
#   .cursor/rules/simple-english.mdc with "alwaysApply: true" applies to every request.
# cursor-install.sh writes the rule file and the hook entries. See docs/other-harnesses.md.
if [ "$STE_HARNESS_NAME" = "cursor" ]; then
  STE_CURSOR_MARK="simple-english-hook:managed"

  ste_cursor_rule_file() {
    [ -n "$STE_PROJECT_DIR" ] || return 1
    printf '%s' "$STE_PROJECT_DIR/.cursor/rules/simple-english.mdc"
  }
  ste_rules_preloaded() {
    local f
    f="$(ste_cursor_rule_file)" && [ -f "$f" ]
  }

  # ste_cursor_write_rule <file> <mode>: write the always-on rule file for a project.
  ste_cursor_write_rule() {
    mkdir -p "$(dirname "$1")"
    {
      printf -- '---\ndescription: Simple English (ASD-STE100) rules. Managed by simple-english-hook.\nglobs:\nalwaysApply: true\n---\n\n'
      printf '<!-- %s level=%s. Generated. Do not edit. Run cursor-install.sh or type /ste to change it. -->\n\n' "$STE_CURSOR_MARK" "$2"
      cat "$STE_DIR/rules/reminder.md"
      [ "$2" = "strict" ] && printf 'STRICT: a linter reads your reply. Replies with violations are sent back for a rewrite.\n'
      printf '\n'
      ste_rules_text
    } > "$1"
  }
  # Remove the rule file, but only one that this plugin wrote (marker check).
  ste_cursor_remove_rule() {
    [ -f "$1" ] && grep -q "$STE_CURSOR_MARK" "$1" && rm -f "$1"
  }
  # After a toggle: keep the project rule file in step with the mode. Touch only
  # projects that hold this plugin's wrapper or rule file (cursor-install.sh ran there).
  # Prints a one-line status for the toggle popup.
  ste_cursor_sync_rule() {
    local f mode
    f="$(ste_cursor_rule_file)" || return 0
    mode="$(ste_mode)"
    if [ "$mode" = "off" ]; then
      ste_cursor_remove_rule "$f" && printf 'Rule file removed: %s' "$f"
      return 0
    fi
    if { [ -f "$f" ] && grep -q "$STE_CURSOR_MARK" "$f"; } || [ -e "$STE_PROJECT_DIR/.cursor/hooks/simple-english-hook.sh" ]; then
      ste_cursor_write_rule "$f" "$mode" && printf 'Rule file updated: %s' "$f"
    else
      printf 'No rule file in this project. Run cursor-install.sh for always-on rules.'
    fi
  }

  # Strict-mode plumbing: afterAgentResponse saves the reply, the stop hook lints it.
  ste_cursor_reply_file() {
    printf '%s/simple-english-hook/reply-%s' "$STE_STATE_DIR" \
      "$(printf '%s' "$1" | jq -r '.conversation_id // "default"' 2>/dev/null)"
  }
  ste_cursor_save_reply() {
    local f
    f="$(ste_cursor_reply_file "$1")"
    mkdir -p "$(dirname "$f")"
    printf '%s' "$1" | jq -r '.text // ""' > "$f"
  }

  # Cursor output shapes. A toggle (third argument set) blocks the prompt and puts
  # the confirmation in the UI popup. It also syncs the project rule file.
  ste_emit() {
    local event="$1" text="$2" sys="${3:-}" msg
    if [ "$event" = "SessionStart" ]; then
      printf '%s' "$text" | jq -Rs '{additional_context: .}'
    elif [ -n "$sys" ]; then
      msg="$({ printf '%s\n' "$text" | grep -E '^STE( MODE IS NOW)?:' | sed 's/\. Reply with one short line.*/./'
               ste_cursor_sync_rule; })"
      printf '%s' "$msg" | jq -Rs '{continue: false, user_message: .}'
    else
      jq -n '{continue: true}'  # beforeSubmitPrompt cannot inject context
    fi
  }
  ste_emit_block() {
    jq -n --arg r "$1" '{followup_message: $r}'
  }
fi
# ==== cursor block end ========================================================
