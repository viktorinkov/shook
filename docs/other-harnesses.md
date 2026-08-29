# Other harnesses

The hook scripts in `hooks/` are plain bash. They run under four harnesses: Claude Code, OpenAI Codex CLI, GitHub Copilot CLI, and Antigravity CLI. `hooks/common.sh` detects the harness and prints the output format that the harness expects. Each harness has its own manifest in this repo.

| Harness | Rules at session start | Reminder on each prompt | Strict (lint gate) | Toggle command | Skill | Badge |
|---|---|---|---|---|---|---|
| Claude Code | yes | yes | yes | `/ste on` | `/ste` | status line |
| Codex CLI | yes | yes | yes | `$ste on` | `$ste` | system message |
| Copilot CLI | yes | no | no | `/simple-english-hook:ste on` (next session) | `/simple-english-hook:ste` | no |
| Antigravity CLI | yes | yes (each model call) | yes | `/ste on` | `/ste` | no |

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
| Claude Code | none of the above | `~/.claude/.simple-english-active` |

Each harness keeps its own global flag. A toggle in Codex does not change the mode in Claude Code. The per-repo file `.claude/ste-mode` and the `STE_MODE` variable apply to all harnesses. The hooks read the project directory from the `cwd` field of the hook input. Antigravity sends `workspacePaths` instead. `STE_HARNESS=<name>` forces a harness. The tests use it.

## Codex CLI

Codex plugin hooks use the same file format as Claude Code. The Codex manifest `.codex-plugin/plugin.json` points at `hooks/hooks.json` and `skills/`. Codex sets `CLAUDE_PLUGIN_ROOT` for compatibility, so the commands in `hooks/hooks.json` work without change.

### Install

```bash
codex plugin marketplace add viktorinkov/simple-english-hook
codex plugin add simple-english-hook@simple-english-hook
```

Then start Codex, open `/hooks`, and trust the three hooks. Start a new thread. Set `STE_PLUGIN_DIR` as shown above.

### Toggle

Type `$ste on`, `$ste strict`, `$ste off`, or `$ste status`. The `$` prefix is the Codex skill mention. `$ste project on` writes `.claude/ste-mode` in the current repo. The hook reads the prompt before the model sees it, so `/ste` and `@ste` also work.

### What works

- `on`: the rules load at session start. Each prompt gets a reminder.
- `strict`: the Stop hook lints `last_assistant_message`. On failure it returns `decision: block`, and Codex asks the model to rewrite.
- Skill: `$ste` is listed as a plugin skill.
- Badge: Codex shows `STE mode: on` as a system message at session start and after each toggle.

### What does not work

- The status line badge. Codex has no status line script.

### Uninstall

```bash
codex plugin remove simple-english-hook@simple-english-hook
codex plugin marketplace remove simple-english-hook
```

Then delete `.simple-english-active` from the plugin data directory. `/hooks` shows the path.

## GitHub Copilot CLI

The Copilot manifest is `.github/plugin/plugin.json`. It points at `hooks/copilot-hooks.json` and `skills/`. Copilot hooks use their own file format (`version`, `sessionStart`, `userPromptSubmitted`, `bash`, `timeoutSec`).

### Install

```bash
copilot plugin marketplace add viktorinkov/simple-english-hook
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
agy plugin install https://github.com/viktorinkov/simple-english-hook
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

## Notes on the sources

The hook contracts come from the official docs and from the CLI binaries. The tests in `tests/run.sh` simulate each harness. Run them with `bash tests/run.sh`.

Where the docs and the ponytail plugin differ, the hooks follow the docs:

- Codex docs say `systemMessage` surfaces as a warning in the UI. Ponytail sends it on every prompt. These hooks send it at session start and after a toggle only.
- Copilot docs say `userPromptSubmitted` output is dropped. Ponytail prints `{}`. These hooks print nothing.
- Ponytail ships no hooks for Antigravity. These hooks use the events from the hooks guide inside the `agy` binary, plus `SessionStart`. That event is not in the guide, but a live run confirmed it.

Four points are not verified in a live session:

- Codex: the exact prompt text that the hook sees after a `$ste` skill mention.
- Copilot: the `COPILOT_PLUGIN_DATA` variable at hook run time. The plugin reference documents it.
- Antigravity: interactive sessions and `--continue`. All four live runs used print mode (`agy -p`).
- Antigravity: `agy plugin install` from a GitHub URL. The local clone path is verified.
