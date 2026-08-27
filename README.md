# Simple English Hook

A hook set for Claude Code. When the `simple-english` skill triggers, it applies its rules. Most replies do not trigger it. With this hook set, the rules apply to every reply.

## Why a hook

When Claude decides that a task fits a skill, the skill loads. Otherwise, it does not load. Most replies never see the rules. A hook runs on every prompt. The harness runs it, not Claude.

## What it does

| Hook | Event | Action |
|---|---|---|
| `SessionStart` | New session, resume, clear, compact | Loads the full STE rule set as context. |
| `UserPromptSubmit` | Every prompt | Adds a short STE reminder. Handles `/ste` commands. |
| `Stop` | End of every reply, `strict` mode only | Runs `ste_lint.py` on the reply. If the reply fails, Claude must rewrite it. |
| Status line | Always | Shows `[STE]` or `[STE:STRICT]` while the mode is on. |

The rule text and the linter come from the installed `simple-english` plugin at run time. Plugin updates apply to the hooks at once.

## Prerequisites

| Tool | Why |
|---|---|
| Claude Code (`claude` CLI) | Runs the hooks and installs the plugin |
| `simple-english@simple-english` plugin | Provides the rule text and `ste_lint.py`. If it is missing, the installer installs it. |
| `jq` | Parses hook input and edits `settings.json` |
| `python3` | Runs the linter in strict mode |

To install the plugin by hand:

```bash
claude plugin marketplace add AminBlg/SimpleEnglish
claude plugin install simple-english@simple-english
```

## Install

1. Clone this repo. Keep the clone where it is. The hook paths point at it.
2. Run `bash install.sh`.
3. Start a new Claude Code session.

The installer checks the prerequisites. If the plugin is missing, the installer installs it. The installer makes a backup of `settings.json` before it writes. You can run it again at any time.

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
3. If the whole team must use it, commit `.claude/ste-mode`. Each team member also runs `install.sh` once.

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
