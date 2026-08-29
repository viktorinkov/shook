#!/usr/bin/env bash
# Hook tests. Each block simulates one harness: it sets the harness env vars,
# pipes sample JSON into the hooks, and checks the output format.
# Run: bash tests/run.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
H="$ROOT/hooks"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

pass=0; fail=0
check() { # check <name> <command...>   passes when the command exits 0
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); printf 'FAIL: %s\n' "$name" >&2; fi
}
has()   { printf '%s' "$1" | grep -q -- "$2"; }
lacks() { ! has "$1" "$2"; }
jqok()  { printf '%s' "$1" | jq -e "$2" >/dev/null; }

# Fake simple-english plugin: rule text plus a stub linter that counts modal verbs.
PLUG="$T/SimpleEnglish"
mkdir -p "$PLUG/output-styles" "$PLUG/evals" "$T/home" "$T/proj"
printf -- '---\nname: simple-english\n---\n\nRULE TEXT MARKER. Write short sentences.\n' > "$PLUG/output-styles/simple-english.md"
cat > "$PLUG/evals/ste_lint.py" <<'PY'
import json, re, sys
text = sys.stdin.read()
words = len(text.split())
n = len(re.findall(r"\b(should|would|could|may|might)\b", text, re.I))
print(json.dumps({"words": words, "violations_total": n,
                  "violations_per_100w": round(100.0 * n / max(words, 1), 2),
                  "longest_sentence_words": words, "violations": {"modal": n}}))
PY
PROJ="$T/proj"
BAD="You should probably refactor this. It would be nicer and it could be faster. We may also want tests, which might help. $(printf 'word %.0s' $(seq 1 40))"
GOOD="Run the tests. Then commit the change. The build takes one minute. $(printf 'word %.0s' $(seq 1 40))"

# hook <script> <stdin json> [VAR=value ...]  Runs a hook with a clean harness environment.
hook() {
  local script="$1" json="$2"; shift 2
  printf '%s' "$json" | env -u STE_MODE -u CLAUDE_PROJECT_DIR -u PLUGIN_DATA -u COPILOT_PLUGIN_DATA \
    -u ANTIGRAVITY_CONVERSATION_ID -u STE_HARNESS -u CURSOR_VERSION -u CLAUDE_PLUGIN_ROOT \
    HOME="$T/home" CLAUDE_CONFIG_DIR="$T/claude" STE_PLUGIN_DIR="$PLUG" "$@" bash "$H/$script" 2>/dev/null
}
flag() { head -n1 "$1" 2>/dev/null; }

# ---- Claude Code ------------------------------------------------------------
CL=(CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_ROOT="$ROOT")
out="$(hook session-start.sh '{"cwd":"'"$PROJ"'"}' STE_MODE=on "${CL[@]}")"
check "claude: session start is SessionStart JSON" jqok "$out" '.hookSpecificOutput.hookEventName == "SessionStart"'
check "claude: session start carries the rules" jqok "$out" '.hookSpecificOutput.additionalContext | test("RULE TEXT MARKER") and test("Level: on") and test("/ste off")'
check "claude: session start mentions the badge" jqok "$out" '.hookSpecificOutput.additionalContext | test("status line badge")'
out="$(hook session-start.sh '{}' "${CL[@]}")"
check "claude: silent when off" test -z "$out"
out="$(hook user-prompt-submit.sh '{"prompt":"/ste strict"}' "${CL[@]}")"
check "claude: /ste strict prints plain text" lacks "$out" '^{'
check "claude: /ste strict confirms the mode" has "$out" 'STE MODE IS NOW: strict (source: global'
check "claude: /ste strict prints the rules" has "$out" 'RULE TEXT MARKER'
check "claude: flag written to CLAUDE_CONFIG_DIR" test "$(flag "$T/claude/.simple-english-active")" = strict
out="$(hook user-prompt-submit.sh '{"prompt":"hello"}' "${CL[@]}")"
check "claude: reminder on a normal prompt" has "$out" 'STE MODE ACTIVE'
check "claude: strict line on a normal prompt" has "$out" 'STRICT:'
out="$(hook stop-gate.sh '{"last_assistant_message":"'"$BAD"'","stop_hook_active":false}' "${CL[@]}")"
check "claude: stop gate blocks a bad reply" jqok "$out" '.decision == "block" and (.reason | test("STE LINT FAILED"))'
out="$(hook stop-gate.sh '{"last_assistant_message":"'"$BAD"'","stop_hook_active":true}' "${CL[@]}")"
check "claude: stop gate runs once per turn" test -z "$out"
out="$(hook stop-gate.sh '{"last_assistant_message":"'"$GOOD"'"}' "${CL[@]}")"
check "claude: stop gate passes a good reply" test -z "$out"
out="$(hook user-prompt-submit.sh '{"prompt":"/ste project off"}' "${CL[@]}")"
check "claude: project file written" test "$(flag "$PROJ/.claude/ste-mode")" = off
check "claude: project file wins" has "$out" 'STE MODE IS NOW: off (source: project'
out="$(hook user-prompt-submit.sh '{"prompt":"/ste project clear"}' "${CL[@]}")"
check "claude: project file cleared" test ! -e "$PROJ/.claude/ste-mode"
out="$(hook user-prompt-submit.sh '{"prompt":"/ste off"}' "${CL[@]}")"
check "claude: /ste off removes the flag" test ! -e "$T/claude/.simple-english-active"
check "claude: /ste off confirms" has "$out" 'STE MODE IS NOW: off'

# ---- Codex CLI --------------------------------------------------------------
# Environment and stdin as observed in Codex CLI 0.149.0 (see docs/other-harnesses.md).
# Codex sets PLUGIN_ROOT, PLUGIN_DATA and the CLAUDE_* aliases. It does not set CLAUDE_PROJECT_DIR.
CX=(PLUGIN_DATA="$T/codex-data" CLAUDE_PLUGIN_DATA="$T/codex-data" CLAUDE_PLUGIN_ROOT="$ROOT" PLUGIN_ROOT="$ROOT")
IN='{"session_id":"01a04aca-7796-7500-bb6c-e66bbf5d49af","turn_id":"01a04aca-781c-7ee3-9cf8-810b08fc401c","transcript_path":"'"$T"'/rollout.jsonl","cwd":"'"$PROJ"'","model":"gpt-5.6-sol","permission_mode":"default"'
out="$(hook user-prompt-submit.sh "$IN"',"hook_event_name":"UserPromptSubmit","prompt":"$ste strict"}' "${CX[@]}")"
check "codex: \$ste strict is UserPromptSubmit JSON" jqok "$out" '.hookSpecificOutput.hookEventName == "UserPromptSubmit"'
check "codex: \$ste strict confirms in additionalContext" jqok "$out" '.hookSpecificOutput.additionalContext | test("STE MODE IS NOW: strict") and test("RULE TEXT MARKER")'
check "codex: systemMessage on toggle" jqok "$out" '.systemMessage == "STE mode: strict"'
check "codex: flag written to PLUGIN_DATA" test "$(flag "$T/codex-data/.simple-english-active")" = strict
check "codex: Claude flag untouched" test ! -e "$T/claude/.simple-english-active"
# The skill picker inserts "$simple-english-hook:ste " (with a trailing space) in front of the arguments.
out="$(hook user-prompt-submit.sh "$IN"',"hook_event_name":"UserPromptSubmit","prompt":"$simple-english-hook:ste  status"}' "${CX[@]}")"
check "codex: picker mention reaches the hook as text" jqok "$out" '.hookSpecificOutput.additionalContext | test("STE MODE IS NOW: strict \\(source: global")'
check "codex: status keeps the flag" test "$(flag "$T/codex-data/.simple-english-active")" = strict
out="$(hook session-start.sh "$IN"',"hook_event_name":"SessionStart","source":"startup"}' "${CX[@]}")"
check "codex: session start JSON" jqok "$out" '.hookSpecificOutput.hookEventName == "SessionStart" and .systemMessage == "STE mode: strict"'
check "codex: session start names \$ste" jqok "$out" '.hookSpecificOutput.additionalContext | test("\\$ste off") and (test("status line badge") | not)'
out="$(hook user-prompt-submit.sh "$IN"',"hook_event_name":"UserPromptSubmit","prompt":"hello"}' "${CX[@]}")"
check "codex: reminder is JSON without systemMessage" jqok "$out" '(.hookSpecificOutput.additionalContext | test("STE MODE ACTIVE")) and (has("systemMessage") | not)'
out="$(hook stop-gate.sh "$IN"',"hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"'"$BAD"'"}' "${CX[@]}")"
check "codex: stop gate blocks" jqok "$out" '.decision == "block"'
check "codex: score written to PLUGIN_DATA" test -s "$T/codex-data/.simple-english-score"
out="$(hook stop-gate.sh "$IN"',"hook_event_name":"Stop","stop_hook_active":true,"last_assistant_message":"'"$BAD"'"}' "${CX[@]}")"
check "codex: stop gate runs once per turn" test -z "$out"
mkdir -p "$PROJ/.claude"; printf 'off\n' > "$PROJ/.claude/ste-mode"
out="$(hook user-prompt-submit.sh "$IN"',"hook_event_name":"UserPromptSubmit","prompt":"hello"}' "${CX[@]}")"
check "codex: project file found through cwd" test -z "$out"
rm -f "$PROJ/.claude/ste-mode"
out="$(hook user-prompt-submit.sh "$IN"',"hook_event_name":"UserPromptSubmit","prompt":"$ste off"}' "${CX[@]}")"
check "codex: \$ste off removes the flag" test ! -e "$T/codex-data/.simple-english-active"

# ---- GitHub Copilot CLI -----------------------------------------------------
CP=(COPILOT_PLUGIN_DATA="$T/copilot-data" PLUGIN_DATA="$T/codex-shadow" PLUGIN_ROOT="$ROOT")
IN='{"cwd":"'"$PROJ"'","sessionId":"s1"'
out="$(hook user-prompt-submit.sh "$IN"',"prompt":"/simple-english-hook:ste strict"}' "${CP[@]}")"
check "copilot: prompt hook prints nothing" test -z "$out"
check "copilot: flag written to COPILOT_PLUGIN_DATA" test "$(flag "$T/copilot-data/.simple-english-active")" = strict
check "copilot: Codex PLUGIN_DATA untouched" test ! -e "$T/codex-shadow/.simple-english-active"
out="$(hook session-start.sh "$IN"',"source":"startup"}' "${CP[@]}")"
check "copilot: session start is {additionalContext}" jqok "$out" '(.additionalContext | test("RULE TEXT MARKER")) and (has("hookSpecificOutput") | not)'
check "copilot: strict downgrades to on" jqok "$out" '.additionalContext | test("Level: on") and test("/simple-english-hook:ste off")'
out="$(hook stop-gate.sh "$IN"',"stopReason":"end_turn","stop_hook_active":false}' "${CP[@]}")"
check "copilot: stop gate is a no-op" test -z "$out"
hook user-prompt-submit.sh "$IN"',"prompt":"/simple-english-hook:ste off"}' "${CP[@]}" >/dev/null
check "copilot: off removes the flag" test ! -e "$T/copilot-data/.simple-english-active"

# ---- Antigravity CLI --------------------------------------------------------
# agy (1.1.22) sends no prompt and no reply text. Both come from the transcript file.
# The hook cwd is the installed plugin copy, and the root hooks.json sets STE_HARNESS.
AG=(ANTIGRAVITY_CONVERSATION_ID=c1 STE_HARNESS=antigravity HOME="$T/aghome")
TP="$T/transcript.jsonl"; : > "$TP"
IN='{"conversationId":"c1","modelName":"m","transcriptPath":"'"$TP"'"'
tstep() { # tstep <index> <source> <type> <content>   appends one transcript step
  jq -nc --argjson i "$1" --arg s "$2" --arg t "$3" --arg c "$4" '{step_index:$i,source:$s,type:$t,content:$c}' >> "$TP"
}
tuser() { tstep "$1" USER_EXPLICIT USER_INPUT "$(printf '<USER_REQUEST>\n%s\n</USER_REQUEST>\n<ADDITIONAL_METADATA>\nx\n</ADDITIONAL_METADATA>' "$2")"; }
tuser 0 "/ste strict"
out="$(hook user-prompt-submit.sh "$IN"',"workspacePaths":[],"invocationNum":0}' "${AG[@]}")"
check "antigravity: /ste strict injects an ephemeral message" jqok "$out" '.injectSteps[0].ephemeralMessage | test("STE MODE IS NOW: strict") and test("RULE TEXT MARKER") and test("project file: none")'
check "antigravity: flag written under ~/.gemini/config" test "$(flag "$T/aghome/.gemini/config/.simple-english-active")" = strict
check "antigravity: Claude flag untouched" test ! -e "$T/claude/.simple-english-active"
out="$(hook session-start.sh "$IN"',"workspacePaths":[]}' "${AG[@]}")"
check "antigravity: session start injects a system message" jqok "$out" '.injectSteps[0].systemMessage.systemMessage | test("RULE TEXT MARKER") and test("Level: strict") and test("/ste off") and (test("status line badge") | not)'
tstep 1 MODEL PLANNER_RESPONSE "STE mode is strict."
out="$(hook user-prompt-submit.sh "$IN"',"workspacePaths":[],"invocationNum":1}' "${AG[@]}")"
check "antigravity: later model calls get the reminder only" jqok "$out" '.injectSteps[0].ephemeralMessage | test("STE MODE ACTIVE") and test("STRICT:") and (test("STE MODE IS NOW") | not)'
tuser 2 "hello"; tstep 3 MODEL PLANNER_RESPONSE "$BAD"
out="$(hook stop-gate.sh "$IN"',"workspacePaths":[],"executionNum":0,"terminationReason":"NO_TOOL_CALL","fullyIdle":true}' "${AG[@]}")"
check "antigravity: stop gate continues on a bad reply" jqok "$out" '.decision == "continue" and (.reason | test("STE LINT FAILED"))'
check "antigravity: score written next to the flag" test -s "$T/aghome/.gemini/config/.simple-english-score"
tstep 4 SYSTEM SYSTEM_MESSAGE "Stop hook blocked termination: STE LINT FAILED (x)"; tstep 5 MODEL PLANNER_RESPONSE "$BAD"
out="$(hook stop-gate.sh "$IN"',"workspacePaths":[],"executionNum":1}' "${AG[@]}")"
check "antigravity: stop gate runs once per turn" test -z "$out"
tuser 6 "again"; tstep 7 MODEL PLANNER_RESPONSE "$GOOD"
out="$(hook stop-gate.sh "$IN"',"workspacePaths":[],"executionNum":0}' "${AG[@]}")"
check "antigravity: stop gate passes a good reply" test -z "$out"
mkdir -p "$T/agplugin/.claude"; printf 'off\n' > "$T/agplugin/.claude/ste-mode"
out="$(cd "$T/agplugin" && hook session-start.sh "$IN"',"workspacePaths":[]}' "${AG[@]}")"
check "antigravity: .claude/ste-mode in the plugin copy is ignored" jqok "$out" '.injectSteps[0].systemMessage.systemMessage | test("Level: strict")'
mkdir -p "$PROJ/.claude"; printf 'off\n' > "$PROJ/.claude/ste-mode"
out="$(hook session-start.sh "$IN"',"workspacePaths":["'"$PROJ"'"]}' "${AG[@]}")"
check "antigravity: project file found through workspacePaths" test -z "$out"
rm -f "$PROJ/.claude/ste-mode"
out="$(hook user-prompt-submit.sh "$IN"',"workspacePaths":[]}' ANTIGRAVITY_CONVERSATION_ID=c1 HOME="$T/aghome")"
check "antigravity: detected from ANTIGRAVITY_CONVERSATION_ID alone" jqok "$out" '.injectSteps[0].ephemeralMessage | test("STE MODE ACTIVE")'
tuser 8 "/ste off"
hook user-prompt-submit.sh "$IN"',"workspacePaths":[]}' "${AG[@]}" >/dev/null
check "antigravity: /ste off removes the flag" test ! -e "$T/aghome/.gemini/config/.simple-english-active"

# ---- Cursor -----------------------------------------------------------------
# Cursor (https://cursor.com/docs/hooks) runs hooks/cursor.sh for four events.
# The dispatcher reads hook_event_name from stdin and sets STE_HARNESS=cursor.
# Cursor sets CLAUDE_PROJECT_DIR as an alias of CURSOR_PROJECT_DIR.
CU=(CLAUDE_PROJECT_DIR="$PROJ")
CFLAG="$T/home/.cursor/.simple-english-active"
out="$(hook cursor.sh '{"hook_event_name":"beforeSubmitPrompt","conversation_id":"c1","cursor_version":"2.4.1","workspace_roots":["'"$PROJ"'"],"prompt":"/ste strict"}' "${CU[@]}")"
check "cursor: /ste strict blocks the prompt" jqok "$out" '.continue == false'
check "cursor: user_message confirms the mode" jqok "$out" '.user_message | test("STE MODE IS NOW: strict \\(source: global") and (test("Reply with") | not)'
check "cursor: user_message says no rule file yet" jqok "$out" '.user_message | test("No rule file")'
check "cursor: flag written under ~/.cursor" test "$(flag "$CFLAG")" = strict
check "cursor: Claude flag untouched" test ! -e "$T/claude/.simple-english-active"
out="$(hook cursor.sh '{"hook_event_name":"sessionStart","session_id":"s1","workspace_roots":["'"$PROJ"'"]}' "${CU[@]}")"
check "cursor: session start is additional_context" jqok "$out" '(.additional_context | test("RULE TEXT MARKER") and test("Level: strict") and test("/ste off")) and (has("hookSpecificOutput") | not)'
check "cursor: no badge mention" jqok "$out" '.additional_context | test("status line badge") | not'
mkdir -p "$PROJ/.cursor/hooks"; printf '#!/bin/sh\n' > "$PROJ/.cursor/hooks/simple-english-hook.sh"
RULE="$PROJ/.cursor/rules/simple-english.mdc"
out="$(hook cursor.sh '{"hook_event_name":"beforeSubmitPrompt","prompt":"/ste strict"}' "${CU[@]}")"
check "cursor: toggle writes the rule file in an installed project" jqok "$out" '.user_message | test("Rule file updated")'
check "cursor: rule file starts with frontmatter" test "$(head -n1 "$RULE")" = "---"
check "cursor: rule file is always-on" grep -q 'alwaysApply: true' "$RULE"
check "cursor: rule file carries the marker" grep -q 'simple-english-hook:managed' "$RULE"
check "cursor: rule file carries the rules" grep -q 'RULE TEXT MARKER' "$RULE"
check "cursor: rule file carries the strict line" grep -q 'STRICT:' "$RULE"
out="$(hook cursor.sh '{"hook_event_name":"sessionStart","workspace_roots":["'"$PROJ"'"]}' "${CU[@]}")"
check "cursor: preloaded rules are not injected twice" jqok "$out" '.additional_context | test("RULE TEXT MARKER") | not'
check "cursor: session start points at the rule file" jqok "$out" '.additional_context | test("simple-english.mdc")'
out="$(hook cursor.sh '{"hook_event_name":"beforeSubmitPrompt","prompt":"hello"}' "${CU[@]}")"
check "cursor: a normal prompt passes through" jqok "$out" '.continue == true and (has("user_message") | not)'
hook cursor.sh '{"hook_event_name":"afterAgentResponse","conversation_id":"c1","text":"'"$BAD"'"}' "${CU[@]}" >/dev/null
check "cursor: reply saved for the stop hook" test -s "$T/home/.cursor/simple-english-hook/reply-c1"
out="$(hook cursor.sh '{"hook_event_name":"stop","conversation_id":"c1","status":"completed","loop_count":0}' "${CU[@]}")"
check "cursor: stop emits a followup_message" jqok "$out" '.followup_message | test("STE LINT FAILED")'
check "cursor: score written next to the flag" test -s "$T/home/.cursor/.simple-english-score"
check "cursor: reply file consumed" test ! -e "$T/home/.cursor/simple-english-hook/reply-c1"
hook cursor.sh '{"hook_event_name":"afterAgentResponse","conversation_id":"c1","text":"'"$BAD"'"}' "${CU[@]}" >/dev/null
out="$(hook cursor.sh '{"hook_event_name":"stop","conversation_id":"c1","status":"completed","loop_count":1}' "${CU[@]}")"
check "cursor: stop runs once per turn (loop_count)" test -z "$out"
hook cursor.sh '{"hook_event_name":"afterAgentResponse","conversation_id":"c1","text":"'"$BAD"'"}' "${CU[@]}" >/dev/null
out="$(hook cursor.sh '{"hook_event_name":"stop","conversation_id":"c1","status":"aborted","loop_count":0}' "${CU[@]}")"
check "cursor: an aborted turn is not linted" test -z "$out"
rm -rf "$T/home/.cursor/simple-english-hook"
hook cursor.sh '{"hook_event_name":"afterAgentResponse","conversation_id":"c1","text":"'"$GOOD"'"}' "${CU[@]}" >/dev/null
out="$(hook cursor.sh '{"hook_event_name":"stop","conversation_id":"c1","status":"completed","loop_count":0}' "${CU[@]}")"
check "cursor: stop passes a good reply" test -z "$out"
out="$(hook cursor.sh '{"hook_event_name":"beforeSubmitPrompt","prompt":"/ste off"}' "${CU[@]}")"
check "cursor: /ste off confirms in the UI" jqok "$out" '(.continue == false) and (.user_message | test("STE MODE IS NOW: off"))'
check "cursor: /ste off removes the flag" test ! -e "$CFLAG"
check "cursor: /ste off removes the rule file" test ! -e "$RULE"
rm -rf "$PROJ/.cursor"
out="$(hook session-start.sh '{}' STE_MODE=on CURSOR_VERSION=2.4.1 CLAUDE_PROJECT_DIR="$PROJ")"
check "cursor: detected from CURSOR_VERSION alone" jqok "$out" '.additional_context | test("Level: on")'
out="$(hook session-start.sh '{}' STE_MODE=on CURSOR_VERSION=2.4.1 CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PROJECT_DIR="$PROJ")"
check "cursor: a nested Claude Code session wins over CURSOR_VERSION" jqok "$out" '.hookSpecificOutput.hookEventName == "SessionStart"'

# ---- cursor-install.sh ------------------------------------------------------
cinst() {
  env -u STE_MODE -u CLAUDE_PROJECT_DIR -u PLUGIN_DATA -u COPILOT_PLUGIN_DATA \
    -u ANTIGRAVITY_CONVERSATION_ID -u STE_HARNESS -u CURSOR_VERSION -u CLAUDE_PLUGIN_ROOT \
    HOME="$T/home" CLAUDE_CONFIG_DIR="$T/claude" STE_PLUGIN_DIR="$PLUG" \
    bash "$ROOT/cursor-install.sh" "$@" >/dev/null 2>&1
}
P2="$T/proj2"; HJ2="$P2/.cursor/hooks.json"
mkdir -p "$P2/.cursor"
printf '{"version":1,"hooks":{"stop":[{"command":"./other-tool.sh"}]}}\n' > "$HJ2"
cinst --project "$P2" strict
check "install: rule file written" grep -q 'RULE TEXT MARKER' "$P2/.cursor/rules/simple-english.mdc"
check "install: rule file is always-on" grep -q 'alwaysApply: true' "$P2/.cursor/rules/simple-english.mdc"
check "install: hooks.json has the four events" jq -e '.version == 1 and (.hooks | keys | sort) == ["afterAgentResponse","beforeSubmitPrompt","sessionStart","stop"]' "$HJ2"
check "install: stop keeps loop_limit 1" jq -e '[.hooks.stop[] | select(.command | test("simple-english-hook"))] | .[0].loop_limit == 1' "$HJ2"
check "install: foreign stop entry survives the merge" jq -e '[.hooks.stop[] | .command] | index("./other-tool.sh") != null' "$HJ2"
check "install: commands use the project-relative path" jq -e '[.hooks[][] | .command | select(test("simple-english-hook"))] | all(. == ".cursor/hooks/simple-english-hook.sh")' "$HJ2"
check "install: wrapper is executable" test -x "$P2/.cursor/hooks/simple-english-hook.sh"
check "install: wrapper calls hooks/cursor.sh" grep -q 'hooks/cursor.sh' "$P2/.cursor/hooks/simple-english-hook.sh"
check "install: project mode file written" test "$(flag "$P2/.claude/ste-mode")" = strict
out="$(printf '%s' '{"hook_event_name":"sessionStart"}' | env -u STE_MODE -u STE_HARNESS -u CURSOR_VERSION -u CLAUDE_PLUGIN_ROOT \
  HOME="$T/home" CLAUDE_CONFIG_DIR="$T/claude" STE_PLUGIN_DIR="$PLUG" CLAUDE_PROJECT_DIR="$P2" \
  bash "$P2/.cursor/hooks/simple-english-hook.sh" 2>/dev/null)"
check "install: the generated wrapper runs end to end" jqok "$out" '.additional_context | test("Level: strict") and (test("RULE TEXT MARKER") | not)'
cinst --project "$P2" off
check "install: off removes the rule file" test ! -e "$P2/.cursor/rules/simple-english.mdc"
check "install: off writes the project mode" test "$(flag "$P2/.claude/ste-mode")" = off
check "install: off keeps the hook entries" grep -q simple-english-hook "$HJ2"
cinst --project "$P2" uninstall
check "uninstall: wrapper removed" test ! -e "$P2/.cursor/hooks/simple-english-hook.sh"
check "uninstall: our entries removed" jq -e '[.hooks[][] | .command] | all(test("simple-english-hook") | not)' "$HJ2"
check "uninstall: foreign entry survives" jq -e '.hooks.stop[0].command == "./other-tool.sh"' "$HJ2"
cinst --user on
check "install --user: hooks.json under ~/.cursor" jq -e '[.hooks[][] | .command] | all(. == "./hooks/simple-english-hook.sh")' "$T/home/.cursor/hooks.json"
check "install --user: global flag on" test "$(flag "$CFLAG")" = on
cinst --user uninstall
check "uninstall --user: flag removed" test ! -e "$CFLAG"
check "uninstall --user: hooks.json removed when only ours" test ! -e "$T/home/.cursor/hooks.json"
check "uninstall --user: wrapper removed" test ! -e "$T/home/.cursor/hooks/simple-english-hook.sh"

# ---- Overrides and missing plugin -------------------------------------------
out="$(hook session-start.sh '{}' STE_MODE=on STE_HARNESS=codex CLAUDE_PROJECT_DIR="$PROJ")"
check "STE_HARNESS override selects the Codex format" jqok "$out" '.systemMessage == "STE mode: on"'
out="$(hook session-start.sh '{}' STE_MODE=on STE_PLUGIN_DIR="$T/nowhere" CLAUDE_PROJECT_DIR="$PROJ")"
check "missing plugin: note names STE_PLUGIN_DIR" jqok "$out" '.hookSpecificOutput.additionalContext | test("STE_PLUGIN_DIR")'

# ---- Manifests --------------------------------------------------------------
for f in hooks/hooks.json hooks/copilot-hooks.json hooks/cursor-hooks.json hooks.json plugin.json .claude-plugin/plugin.json \
         .claude-plugin/marketplace.json .codex-plugin/plugin.json .agents/plugins/marketplace.json \
         .github/plugin/plugin.json .github/plugin/marketplace.json; do
  check "valid JSON: $f" jq -e . "$ROOT/$f"
done
check "claude hooks.json keeps its three events" jq -e '.hooks | keys == ["SessionStart","Stop","UserPromptSubmit"]' "$ROOT/hooks/hooks.json"
check "codex manifest reuses hooks/hooks.json and skills" jq -e '.hooks == "./hooks/hooks.json" and .skills == "./skills/"' "$ROOT/.codex-plugin/plugin.json"
check "copilot hooks use the native format" jq -e '.version == 1 and (.hooks | keys == ["sessionStart","userPromptSubmitted"]) and (.hooks.sessionStart[0].bash | test("PLUGIN_ROOT"))' "$ROOT/hooks/copilot-hooks.json"
check "copilot manifest points at copilot-hooks.json" jq -e '.hooks == "hooks/copilot-hooks.json" and .skills == "skills/"' "$ROOT/.github/plugin/plugin.json"
check "antigravity hooks.json is one named hook with agy events" jq -e 'keys == ["simple-english-hook"] and (.["simple-english-hook"] | keys == ["PreInvocation","SessionStart","Stop"])' "$ROOT/hooks.json"
check "antigravity hooks use relative paths and set the harness" jq -e '[.["simple-english-hook"][][] | .command] | length == 3 and all(test("^STE_HARNESS=antigravity bash hooks/[a-z-]+\\.sh$"))' "$ROOT/hooks.json"
check "antigravity plugin.json has name and description only" jq -e '.name == "simple-english-hook" and keys == ["description","name"]' "$ROOT/plugin.json"
check "cursor template has the four events" jq -e '.version == 1 and (.hooks | keys | sort) == ["afterAgentResponse","beforeSubmitPrompt","sessionStart","stop"]' "$ROOT/hooks/cursor-hooks.json"
check "cursor template caps the stop loop and uses one command" jq -e '.hooks.stop[0].loop_limit == 1 and ([.hooks[][] | .command] | all(. == ".cursor/hooks/simple-english-hook.sh"))' "$ROOT/hooks/cursor-hooks.json"
check "gemini directory removed" test ! -e "$ROOT/gemini"
v="$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"
for f in .codex-plugin/plugin.json .github/plugin/plugin.json; do
  check "version $v in $f" test "$(jq -r .version "$ROOT/$f")" = "$v"
done

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
