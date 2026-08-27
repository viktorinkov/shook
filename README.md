# Simple English Hook

A hook set for Claude Code. The `simple-english` skill applies its rules only when it triggers. With this hook set, the rules apply to every reply.

## Why a hook

When Claude decides that a task fits a skill, the skill loads. Otherwise, it does not load. Most replies never see the rules. A hook runs on every prompt. The harness runs it, not Claude.

## What it does

| Hook | Event | Action |
|---|---|---|
| `SessionStart` | New session, resume, clear, compact | Loads the full STE rule set as context. |
| `UserPromptSubmit` | Every prompt | Adds a short STE reminder. Handles `/ste` commands. |
| `Stop` | End of every reply, `strict` mode only | Runs `ste_lint.py` on the reply. If the reply fails, Claude must rewrite it. |
| Status line | Always | When the mode is on, shows `[STE]` or `[STE:STRICT]`. |

The rule text and the linter come from the installed `simple-english` plugin. If the plugin is not installed, the hooks use the copies in `rules/` and `vendor/`.

## Install

1. Make sure that `jq` and `python3` are installed.
2. Run `bash install.sh`.
3. Start a new Claude Code session.

The installer makes a backup of `settings.json` before it writes. You can run it again after a plugin update.

## Enable it

The hooks are installed once per user. They run in every repo. The **mode** decides what they do. The mode has three scopes.

| Scope | How to set it | Where it lives |
|---|---|---|
| Global | `/ste on`, `/ste strict`, `/ste off` | `~/.claude/.simple-english-active` |
| One repo | `/ste project on`, `/ste project strict`, `/ste project off`, `/ste project clear` | `<repo>/.claude/ste-mode` |
| One session or one repo, fixed | `STE_MODE=strict` in the environment, or `"env": {"STE_MODE": "strict"}` in `<repo>/.claude/settings.json` | environment |

Order of precedence: environment, then the repo file, then the global flag, then off.

`/ste status` shows the current mode and its source.

### Enable it in an existing repo

1. Open Claude Code in the repo.
2. Type `/ste project strict` (or `on`).
3. Commit `.claude/ste-mode` if the whole team must use it. Each team member also runs `install.sh` once.

To turn the mode off for one repo only, type `/ste project off`. The repo file wins over the global flag.

### The status line

When the mode is on, the status line shows `[STE]`. In strict mode it shows `[STE:STRICT]`. When the mode is off, it shows nothing.

## Tune the lint gate

When all three conditions are true, the gate blocks the reply:

- The reply has at least `STE_MIN_WORDS` words (default 40).
- The reply has at least `STE_MIN_TOTAL` violations (default 2).
- The density is above `STE_MAX_PER_100W` violations per 100 words (default 1.0).

Set these as environment variables, or edit the policy block in `hooks/stop-gate.sh`. The linter is a regex pass. It undercounts, and it can flag a valid word inside a quote. A tight gate makes Claude rewrite short, correct replies. A loose gate lets slop through.

The gate runs at most one rewrite per turn. Claude Code sets `stop_hook_active` on the second pass, and the hook exits.

## Check that it works

- Run `/hooks`. The three hooks appear under **User Settings**.
- Look at the status line. The badge shows the mode.
- Type `/ste status`. Claude replies with the mode.

## Uninstall

1. Remove the three hook entries that contain `Simple English Hook` from `~/.claude/settings.json`.
2. Remove the badge line from your status line script. It ends with `# simple-english-hook`.
3. Delete `~/.claude/skills/ste` and `~/.claude/.simple-english-active`.
4. Delete `.claude/ste-mode` from any repo that has one.
