# Other harnesses

The hook scripts in `hooks/` are plain bash. They run under five harnesses: Claude Code, OpenAI Codex CLI, GitHub Copilot CLI, Antigravity CLI, and Cursor. `hooks/common.sh` detects the harness and prints the output format that the harness expects. Each harness has its own manifest in this repo.

| Harness | Rules at session start | Reminder on each prompt | Strict (lint gate) | Toggle command | Skill | Badge |
|---|---|---|---|---|---|---|
| Claude Code | yes | yes | yes | `/ste on` | `/ste` | status line |
| Codex CLI | yes | yes | yes | `$ste on` | `$ste` | system message |
| Copilot CLI | yes | no | no | `/simple-english-hook:ste on` (next session) | `/simple-english-hook:ste` | no |
| Antigravity CLI | yes | yes (each model call) | yes | `/ste on` | `/ste` | no |
| Cursor | yes | yes (always-on rule file) | yes (docs only, not verified live) | `/ste on` | no | toggle popup |

Requirements: bash, `jq`, and `python3` (strict mode only).

## Prerequisite: the simple-english plugin files

The rule text and the linter come from [AminBlg/SimpleEnglish](https://github.com/AminBlg/SimpleEnglish). Claude Code installs that plugin under `~/.claude/plugins`. The other harnesses do not. Clone the repo and point `STE_PLUGIN_DIR` at the clone:

```bash
git clone https://github.com/AminBlg/SimpleEnglish ~/SimpleEnglish
export STE_PLUGIN_DIR=~/SimpleEnglish
```

Put the `export` line in your shell profile. The hooks read `STE_PLUGIN_DIR` first. If it is unset, they look in `~/.claude/plugins` as before. If they find nothing, the model gets a note that names the missing plugin.

## How the scripts detect the harness

| Harness | Detection | Global mode flag |
|---|---|---|
| Codex CLI | `PLUGIN_DATA` is set | `$PLUGIN_DATA/.simple-english-active` |
| Copilot CLI | `COPILOT_PLUGIN_DATA` is set | `$COPILOT_PLUGIN_DATA/.simple-english-active` |
| Antigravity CLI | `STE_HARNESS=antigravity` from the root `hooks.json`, or `ANTIGRAVITY_CONVERSATION_ID` is set | `~/.gemini/config/.simple-english-active` |
| Cursor | `STE_HARNESS=cursor` from `hooks/cursor.sh`, or `CURSOR_VERSION` is set and `CLAUDE_PLUGIN_ROOT` is not | `~/.cursor/.simple-english-active` |
| Claude Code | none of the above | `~/.claude/.simple-english-active` |

Each harness keeps its own global flag. A toggle in Codex does not change the mode in Claude Code. The per-repo file `.claude/ste-mode` and the `STE_MODE` variable apply to all harnesses. The hooks read the project directory from the `cwd` field of the hook input. Antigravity sends `workspacePaths` instead. `STE_HARNESS=<name>` forces a harness. The tests use it.

## Codex CLI

Verified in a live session with Codex CLI 0.149.0 on macOS. Codex plugin hooks use the same file format as Claude Code. The Codex manifest `.codex-plugin/plugin.json` points at `hooks/hooks.json` and `skills/`. Codex sets `CLAUDE_PLUGIN_ROOT` as an alias of `PLUGIN_ROOT`, so the commands in `hooks/hooks.json` work without change.

### Install

```bash
codex plugin marketplace add viktorinkov/shook
codex plugin add simple-english-hook@simple-english-hook
```

The first command clones the repo to `~/.codex/.tmp/marketplaces/simple-english-hook` and adds `[marketplaces.simple-english-hook]` to `~/.codex/config.toml`. The second copies the plugin to `~/.codex/plugins/cache/simple-english-hook/simple-english-hook/<version>/` and adds `[plugins."simple-english-hook@simple-english-hook"]`. `codex plugin list` shows the result.

Set `STE_PLUGIN_DIR` as shown above. Then start Codex in a project. At the first start Codex shows `Hooks need review`. Choose `Review hooks`, open each event, select the `simple-english-hook` entry, and press `t`. `Trust all` also trusts hooks from other plugins and from `~/.codex/hooks.json`, so read the list first. The `/hooks` panel shows the same list at any time. Codex records the trust in `[hooks.state]` in `config.toml`. Scripts can run `codex exec --dangerously-bypass-hook-trust` instead. That flag skips the review for one run.

For a local checkout, write a marketplace file with `"source": "local"` and a `path` to the checkout. Then run `codex plugin marketplace add <folder>` on the folder that holds `.agents/plugins/marketplace.json`. The repo file uses a Git URL, so the repo folder itself is not a local marketplace.

### Toggle

Type `$ste on`, `$ste strict`, `$ste off`, or `$ste status`. The `$` opens the Codex skill picker. The picker lists `ste (simple-english-hook)` and inserts `$simple-english-hook:ste`. The hook receives the prompt as typed. Two observed values are `$ste on` and `$simple-english-hook:ste  status`. The hook accepts both forms. `$ste project on` writes `.claude/ste-mode` in the current repo. In the TUI, `/` opens the Codex command menu and `@` opens the file picker. `/ste` and `@ste` are not verified.

### What Codex sends to the hooks

All events carry `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `model`, and `permission_mode`. `SessionStart` adds `source`. `UserPromptSubmit` adds `turn_id` and `prompt`. `Stop` adds `turn_id`, `stop_hook_active`, and `last_assistant_message`. Codex reads `hookSpecificOutput.additionalContext`, `systemMessage`, and `decision: block` with `reason` from the hook output.

Hook commands run in the project directory with the shell environment plus `PLUGIN_ROOT`, `PLUGIN_DATA`, `CLAUDE_PLUGIN_ROOT`, and `CLAUDE_PLUGIN_DATA`. `CLAUDE_PROJECT_DIR` is not set, so the hooks read `cwd` from the input. `STE_PLUGIN_DIR` and `STE_MODE` from your shell profile reach the hooks. `PLUGIN_DATA` is `~/.codex/plugins/data/simple-english-hook-simple-english-hook`. Codex does not create that folder. The hook creates it at the first toggle.

### What works

- `on`: the rules load at session start, and each prompt gets the reminder. In the TUI, the SessionStart hooks run at the first prompt, not at launch. A 113-word test reply had 2 violations, 1.77 per 100 words, and a longest sentence of 15 words.
- `strict`: the Stop hook lints `last_assistant_message`. On `decision: block`, Codex starts a rewrite turn with the reason. The second Stop call has `stop_hook_active: true`, so the hook exits. Both replies stay in the transcript. A 128-word test reply had 0 violations. The hook writes `.simple-english-score` next to the flag.
- Skill: `ste (simple-english-hook)` appears in the `$` picker.
- Badge: the TUI shows `SessionStart (completed) says: STE mode: on` and the same line after each toggle. The rule text appears as collapsed `hook context:` lines.
- `codex exec`: the same three hooks run. Use `--dangerously-bypass-hook-trust` when the hooks are not trusted yet.

### What does not work

- The status line badge. Codex has no status line script.
- `systemMessage` in `codex exec --json` output. The JSONL stream has no event for it.
- The look of a blocked reply in the TUI is not verified. Only `codex exec` runs were checked in strict mode.

### Uninstall

```bash
codex plugin remove simple-english-hook@simple-english-hook
codex plugin marketplace remove simple-english-hook
```

`codex plugin remove` keeps the data folder. Delete `~/.codex/plugins/data/simple-english-hook-simple-english-hook/`. It holds `.simple-english-active` and `.simple-english-score`. The empty folder `~/.codex/plugins/cache/simple-english-hook/` also stays. Delete it if you want a clean cache.

## GitHub Copilot CLI

The Copilot manifest is `.github/plugin/plugin.json`. It points at `hooks/copilot-hooks.json` and `skills/`. Copilot hooks use their own file format (`version`, `sessionStart`, `userPromptSubmitted`, `bash`, `timeoutSec`).

### Install

```bash
copilot plugin marketplace add viktorinkov/shook
copilot plugin install simple-english-hook@simple-english-hook
```

Set `STE_PLUGIN_DIR` as shown above. Start a new Copilot session.

### Toggle

Type `/simple-english-hook:ste on` or `/simple-english-hook:ste off`. Copilot drops the output of prompt hooks, so the confirmation line does not show. The hook still writes the flag. The new mode applies at the next session start. To set the mode for one session, start Copilot with `STE_MODE=on copilot`.

### What works

- `on`: the rules load at session start. Copilot reads `additionalContext` from the `sessionStart` hook.
- Skill: `/simple-english-hook:ste` is listed as a plugin skill.

### What does not work

- The reminder on each prompt. Copilot ignores `userPromptSubmitted` output from command hooks.
- `strict`. The `agentStop` event can block, but its input has no reply text, so there is nothing to lint. The hooks treat `strict` as `on`. `stop-gate.sh` exits at once under Copilot.
- The badge.

### Uninstall

```bash
copilot plugin uninstall simple-english-hook
```

Then delete `.simple-english-active` from the plugin data directory under `~/.copilot`.

## Antigravity CLI

Antigravity CLI (`agy`) replaced Gemini CLI. It reads a plugin from a directory with `plugin.json` and `hooks.json` at the root. The root `hooks.json` in this repo is that file. It uses named hooks: the top-level key is the hook name, and the event lists sit under it. Claude Code and Codex read `hooks/hooks.json`, so the two files do not conflict.

The events differ from Claude Code. `SessionStart` runs once per conversation. `PreInvocation` runs before every model call, also after tool calls. `Stop` runs when the turn ends. The Gemini CLI names (`BeforeAgent`, `AfterAgent`) do nothing in `agy`. It ignores them without an error.

### Install

```bash
git clone https://github.com/AminBlg/SimpleEnglish ~/SimpleEnglish
export STE_PLUGIN_DIR=~/SimpleEnglish
agy plugin install https://github.com/viktorinkov/shook
```

`agy plugin install` also takes a local clone path. It copies the whole directory to `~/.gemini/config/plugins/simple-english-hook/`. Run `agy plugin validate .` in the clone to check the manifest. Then start a new `agy` session.

### Toggle

Type `/ste on`, `/ste strict`, `/ste off`, or `/ste status`. Antigravity sends no prompt text to its hooks. The `PreInvocation` hook reads the newest user message from the transcript file. The text arrives verbatim, so `/ste project strict` also works. The confirmation line reaches the model as an ephemeral message, and the model repeats it.

### What works

- `on`: the rules load at session start as a system message. That message stays in the conversation. Each model call gets the reminder as an ephemeral message.
- `strict`: the `Stop` hook lints the last model reply from the transcript. On failure it returns `{"decision": "continue", "reason": ...}`. Antigravity shows the reason to the model as a system message and runs one more call. The hook finds that message in the transcript and does not block twice.
- Skill: `agy` lists `ste` under `/skills`. In print mode, `agy -p "/ste strict"` reaches the hook as plain text.
- Global flag: `~/.gemini/config/.simple-english-active`. The score file sits next to it.

### What does not work

- The badge. Antigravity has no status line and no UI slot for hook messages.
- The per-repo file when `workspacePaths` is empty. In print mode (`agy -p`) outside a project, `agy` sends no workspace path. Use the global flag or `STE_MODE`.
- `${extensionPath}` in hook commands. `agy` 1.1.22 expands it to an empty string. The commands use relative paths, because `agy` runs hooks from the plugin directory.

### Uninstall

```bash
agy plugin uninstall simple-english-hook
```

Then delete `~/.gemini/config/.simple-english-active` and `~/.gemini/config/.simple-english-score`.

### Hook contract (agy 1.1.22)

Observed in live runs. Stdin is one JSON object with camelCase keys. Common fields: `conversationId`, `workspacePaths`, `transcriptPath`, `artifactDirectoryPath`, `modelName`. `PreInvocation` adds `invocationNum` and `initialNumSteps`. `Stop` adds `executionNum`, `terminationReason`, `error`, and `fullyIdle`. No field holds the prompt or the reply. The environment holds `ANTIGRAVITY_CONVERSATION_ID`.

The transcript is JSON lines with `step_index`, `source`, `type`, and `content`. The user message is `type: USER_INPUT`, with the text inside `<USER_REQUEST>` tags. The reply is `source: MODEL`, `type: PLANNER_RESPONSE`. A Stop continuation appears as `type: SYSTEM_MESSAGE` with the reason.

Output: `SessionStart` and `PreInvocation` take `{"injectSteps": [...]}`. A step is `{"ephemeralMessage": "..."}` or `{"systemMessage": {"systemMessage": "..."}}`. `Stop` takes `{"decision": "continue", "reason": "..."}`. Any other decision lets the agent stop.

## Cursor

Cursor is an IDE with hooks and rule files. It loads no plugins, so `cursor-install.sh` writes the files that Cursor reads. Support has two parts. A project rule file makes the rules always on. Four hooks add the `/ste` toggle and strict mode. This section comes from the Cursor docs and from the simulated tests in `tests/run.sh`. No live Cursor session verified it. We cannot run the Cursor IDE headless.

### Prerequisites

- A Cursor version with hooks and `hooks.json` schema version 1. The hooks reference names no minimum version.
- bash, `jq`, and `python3` (strict mode only).
- The simple-english plugin files. Set `STE_PLUGIN_DIR` as shown above.
- A clone of this repo. The hook scripts run from the clone.

### Install

```bash
git clone https://github.com/viktorinkov/simple-english-hook ~/simple-english-hook
cd <your-project>
bash ~/simple-english-hook/cursor-install.sh strict
```

The script writes four files into the project:

- `.cursor/rules/simple-english.mdc` — the reminder and the full rule set, with `alwaysApply: true`. Cursor attaches such a rule to every request.
- `.cursor/hooks.json` — entries for `sessionStart`, `beforeSubmitPrompt`, `afterAgentResponse`, and `stop`. The script merges them into an existing file. Entries from other tools stay.
- `.cursor/hooks/simple-english-hook.sh` — a wrapper that calls `hooks/cursor.sh` in the clone. The wrapper holds the absolute path, so `hooks.json` holds a short relative path.
- `.claude/ste-mode` — the per-repo mode file, shared with the other harnesses.

`--project DIR` targets another project. `--user` writes the hooks and the global flag into `~/.cursor/` instead. The user scope has no rule file. Cursor user rules are plain text in the settings, not files. With `--user`, the rules reach the model at session start only. Cursor watches `hooks.json` and reloads it on save. Restart Cursor if the hooks do not load.

### Toggle

Type `/ste on`, `/ste strict`, `/ste off`, or `/ste status` in the Agent chat. The `beforeSubmitPrompt` hook reads the prompt, updates the flag, and returns `{"continue": false}`. Cursor then drops the prompt and shows the `user_message` confirmation. The toggle costs no model turn. The hook also rewrites or removes the project rule file to match the new mode. It only touches rule files with its own `simple-english-hook:managed` marker. `bash cursor-install.sh on|strict|off|status` does the same from the shell.

There is no `ste` skill for Cursor. Cursor 2.4 added skills: `.cursor/skills/<name>/SKILL.md`, invoked as `/name`. The skills docs do not say that arguments after `/name` reach the hooks as text. So the toggle stays a plain text prompt. If Cursor consumes `/ste` before the hook sees it, use the install script.

### What works

Per the docs. No live session verified it.

- `on`: the rule file puts the reminder and the full rules into every request. This one file replaces the session-start injection and the per-prompt reminder. The `sessionStart` hook adds the mode header through `additional_context`. When the rule file exists, the hook skips the rule text to avoid duplication.
- `strict`: `afterAgentResponse` delivers each reply as `{"text": ...}`, and `hooks/cursor.sh` saves the last one. The `stop` hook lints the saved text. On failure it returns `{"followup_message": ...}` with the lint report. Cursor submits that as the next user message, and the model rewrites the reply. `loop_count` and `"loop_limit": 1` cap it at one rewrite per turn.
- The toggle. The confirmation shows in the Cursor UI as `user_message`.
- The score file `~/.cursor/.simple-english-score`, next to the global flag.

### What does not work

- A reminder injected on each prompt. `beforeSubmitPrompt` output is `continue` and `user_message` only. The always-on rule file covers the reminder instead.
- The status line badge. The toggle popup is the only UI surface.
- An `ste` skill. See the Toggle section.
- A hidden rewrite request. The `followup_message` appears in the chat as a user message.
- Cloud agents. The docs list `sessionStart` and `beforeSubmitPrompt` as unsupported there. A forum report also shows `stop` and `afterAgentResponse` as not firing in cloud agents.

### Uninstall

```bash
cd <your-project>
bash ~/simple-english-hook/cursor-install.sh uninstall
bash ~/simple-english-hook/cursor-install.sh --user uninstall
```

The project uninstall removes the rule file, the wrapper, and this plugin's entries in `.cursor/hooks.json`. It keeps `.claude/ste-mode`, because the other harnesses read it. Delete that file by hand if no harness needs it. The user uninstall also deletes the flag, the score file, and the saved replies.

### Hook contract (docs)

Config files: `~/.cursor/hooks.json` (user) and `<project>/.cursor/hooks.json` (project). The shape is `{"version": 1, "hooks": {"<event>": [{"command": ..., "timeout": ..., "loop_limit": ...}]}}`. A hook gets one JSON object on stdin and answers with one JSON object on stdout. Common input fields include `conversation_id`, `hook_event_name`, `workspace_roots`, and `cursor_version`. Hook processes get `CURSOR_PROJECT_DIR`, `CURSOR_VERSION`, and `CLAUDE_PROJECT_DIR` as an alias. Project hook commands run from the project root. The events this plugin uses:

| Event | Input used | Output used |
|---|---|---|
| `sessionStart` | `session_id` | `{"additional_context": ...}` |
| `beforeSubmitPrompt` | `prompt` | `{"continue": bool, "user_message": ...}` |
| `afterAgentResponse` | `text`, `conversation_id` | none (the hook saves the text) |
| `stop` | `status`, `loop_count`, `conversation_id` | `{"followup_message": ...}` |

Sources: <https://cursor.com/docs/hooks> (events, stdin fields, output keys, config locations, environment variables), <https://cursor.com/docs/context/rules> (`.mdc` frontmatter, `alwaysApply`, user rules as plain text), <https://cursor.com/docs/skills> (skill files, `/name` invocation), <https://forum.cursor.com/t/cursor-cloud-agents-do-not-run-afteragentresponse-or-stop-hooks/159929> (cloud agents).

## Notes on the sources

The hook contracts come from the official docs and from the CLI binaries. The tests in `tests/run.sh` simulate each harness. Run them with `bash tests/run.sh`.

Where the docs and the ponytail plugin differ, the hooks follow the docs:

- Codex shows `systemMessage` as `<Event> (completed) says: ...` in the TUI. Ponytail sends it on every prompt. These hooks send it at session start and after a toggle only.
- Copilot docs say `userPromptSubmitted` output is dropped. Ponytail prints `{}`. These hooks print nothing.
- Ponytail ships no hooks for Antigravity. These hooks use the events from the hooks guide inside the `agy` binary, plus `SessionStart`. That event is not in the guide, but a live run confirmed it.
- Ponytail ships a static `.cursor/rules/ponytail.mdc` and no Cursor hooks. This plugin generates the rule file instead, because the rule text lives in the simple-english plugin.

Status of the open points in a live session:

- Codex: verified. The hook sees the skill mention as text, for example `$simple-english-hook:ste  status`. See the Codex section.
- Copilot: the `COPILOT_PLUGIN_DATA` variable at hook run time. The plugin reference documents it.
- Antigravity: interactive sessions and `--continue`. All four live runs used print mode (`agy -p`).
- Antigravity: `agy plugin install` from a GitHub URL. The local clone path is verified.
- Cursor: everything. No live Cursor run happened. The contract comes from the sources in the Cursor section.
