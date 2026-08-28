# Simple English Hook

A hook set for Claude Code. When the `simple-english` skill triggers, it applies its rules. Most replies do not trigger it. With this hook set, the rules apply to every reply.

## Origin

This project is a companion to **[AminBlg/SimpleEnglish](https://github.com/AminBlg/SimpleEnglish)**. That plugin brings ASD-STE100 Simplified Technical English to Claude Code and other agents. All rule text and the linter come from that plugin. This repo adds only the hooks, the `/ste` command, the status line badge, and the installer. The plugin is a prerequisite. The installer installs it.

## Why a hook

When Claude decides that a task fits a skill, the skill loads. Otherwise, it does not load. Most replies never see the rules. A hook runs on every prompt. The harness runs it, not Claude.

## What it does

| Hook | Event | Action |
|---|---|---|
| `SessionStart` | New session, resume, clear, compact | Loads the full STE rule set as context. |
| `UserPromptSubmit` | Every prompt | Adds a short STE reminder. Handles `/ste` commands. |
| `Stop` | End of every reply, `strict` mode only | Runs `ste_lint.py` on the reply. If the reply fails, Claude must rewrite it. |
| Status line (optional) | Always | Shows `[STE]` or `[STE:STRICT]` while the mode is on. |

The rule text and the linter come from the installed `simple-english` plugin at run time. Plugin updates apply to the hooks at once.

## Install

Run these four commands. The first two install the prerequisite plugin. The last two install this one.

```bash
claude plugin marketplace add AminBlg/SimpleEnglish
claude plugin install simple-english@simple-english
claude plugin marketplace add viktorinkov/simple-english-hook
claude plugin install simple-english-hook@simple-english-hook
```

Then start a new Claude Code session. The mode is off until you type `/ste on`.

Requirements: Claude Code, `jq`, and `python3` (strict mode only).

### Optional: the status line badge

A plugin cannot change the status line, so this step is by hand. Ask Claude: *install the STE status line badge*. Claude runs `statusline-install.sh` from the plugin folder. The script adds one line to your status line script. If you have no status line, the script creates one.

### Update

```bash
claude plugin marketplace update simple-english-hook
claude plugin update simple-english-hook@simple-english-hook
```

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
3. If the whole team must use it, commit `.claude/ste-mode`. Each team member also installs the plugin once.

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

1. Run `claude plugin uninstall simple-english-hook@simple-english-hook`.
2. If you installed the badge, remove the line that ends with `# simple-english-hook` from your status line script.
3. Delete `~/.claude/.simple-english-active` and `~/.claude/simple-english-hook/`.
4. Delete `.claude/ste-mode` from any repo that has one.
