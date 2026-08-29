# Other harnesses

The hook scripts in `hooks/` are plain bash. They run under four harnesses: Claude Code, OpenAI Codex CLI, GitHub Copilot CLI, and Gemini CLI. `hooks/common.sh` detects the harness and prints the output format that the harness expects. Each harness has its own manifest in this repo.

| Harness | Rules at session start | Reminder on each prompt | Strict (lint gate) | Toggle command | Skill | Badge |
|---|---|---|---|---|---|---|
| Claude Code | yes | yes | yes | `/ste on` | `/ste` | status line |
| Codex CLI | yes | yes | yes | `$ste on` | `$ste` | system message |
| Copilot CLI | yes | no | no | `/simple-english-hook:ste on` (next session) | `/simple-english-hook:ste` | no |
| Gemini CLI | yes | yes | yes | `/ste on` | `/ste` | system message |

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
| Gemini CLI | `GEMINI_SESSION_ID` is set | `~/.gemini/.simple-english-active` |
| Claude Code | none of the above | `~/.claude/.simple-english-active` |

Each harness keeps its own global flag. A toggle in Codex does not change the mode in Claude Code. The per-repo file `.claude/ste-mode` and the `STE_MODE` variable apply to all harnesses. The hooks read the project directory from the `cwd` field of the hook input. `STE_HARNESS=<name>` forces a harness. The tests use it.

## Codex CLI

Verified in a live session with Codex CLI 0.149.0 on macOS. Codex plugin hooks use the same file format as Claude Code. The Codex manifest `.codex-plugin/plugin.json` points at `hooks/hooks.json` and `skills/`. Codex sets `CLAUDE_PLUGIN_ROOT` as an alias of `PLUGIN_ROOT`, so the commands in `hooks/hooks.json` work without change.

### Install

```bash
codex plugin marketplace add viktorinkov/simple-english-hook
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

## Gemini CLI

Gemini CLI loads `hooks/hooks.json` from the root of an extension. That file holds the Claude Code events, and Gemini uses other event names (`BeforeAgent`, `AfterAgent`). So the Gemini extension lives in the `gemini/` folder. Its `hooks/hooks.json` maps the Gemini events to the shared scripts through `${extensionPath}/../hooks/`. The extension must stay inside the clone, so link it. Do not copy it.

### Install

```bash
git clone https://github.com/AminBlg/SimpleEnglish ~/SimpleEnglish
git clone https://github.com/viktorinkov/simple-english-hook ~/simple-english-hook
gemini extensions link ~/simple-english-hook/gemini
```

Gemini asks you to accept the hooks. Set `STE_PLUGIN_DIR` as shown above. Start a new Gemini session.

### Toggle

Type `/ste on`, `/ste strict`, `/ste off`, or `/ste status`. `gemini/commands/ste.toml` defines the command. It sends `/ste <args>` as the prompt, and the `BeforeAgent` hook reads it. `/ste project on` writes `.claude/ste-mode` in the current repo.

### What works

- `on`: the rules load at session start. Each prompt gets a reminder.
- `strict`: the `AfterAgent` hook lints `prompt_response`. On failure it returns `decision: block`, and Gemini runs a retry turn with the reason.
- Skill: `gemini/skills` links to the shared `skills/` folder.
- Badge: Gemini shows `STE mode: on` as a system message at session start and after each toggle.

### What does not work

- `gemini extensions install`. The copied extension loses the link to `hooks/`. Use `link`.
- The status line badge.

### Uninstall

```bash
gemini extensions uninstall simple-english-hook
```

Then delete `~/.gemini/.simple-english-active`.

## Notes on the sources

The hook contracts come from the official docs and from the CLI binaries. The tests in `tests/run.sh` simulate each harness. Run them with `bash tests/run.sh`.

Where the docs and the ponytail plugin differ, the hooks follow the docs:

- Codex shows `systemMessage` as `<Event> (completed) says: ...` in the TUI. Ponytail sends it on every prompt. These hooks send it at session start and after a toggle only.
- Copilot docs say `userPromptSubmitted` output is dropped. Ponytail prints `{}`. These hooks print nothing.
- Ponytail ships no hooks for Gemini. These hooks use the Gemini events from the hooks reference. They live in a subfolder, so Claude Code and Gemini do not read the same `hooks/hooks.json`.

Status of three points in a live session:

- Codex: verified. The hook sees the skill mention as text, for example `$simple-english-hook:ste  status`. See the Codex section.
- Copilot: the `COPILOT_PLUGIN_DATA` variable at hook run time. The plugin reference documents it.
- Gemini: the `/ste` command expands before the `BeforeAgent` hook runs. The custom command docs say so.
