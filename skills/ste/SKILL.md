---
name: ste
description: Toggle Simple English (ASD-STE100) mode and tune the lint gate. Usage - /ste on | strict | off | status | config | set <key> <value> | unset <key> | uninstall | project on|strict|off|clear|set|unset
argument-hint: on | strict | off | status | config | set <key> <value> | unset <key> | uninstall | project <mode>
---

A hook read this command before you saw it. The hook updated the mode file or the config file and printed the result as context above.

Reply with one short line that confirms the mode and the source, for example: "STE mode: strict (project)."

Do not run tools. Do not do other work in this reply.

On GitHub Copilot CLI the hook output is dropped. If no "STE MODE IS NOW" or "STE CONFIG" line is above, reply: "STE change saved. It applies at the next session start." On Codex the command is typed as `$ste on`. The Codex skill picker inserts it as `$simple-english-hook:ste`. The hook accepts both forms. On Antigravity CLI the hook reads the command from the transcript, and the result arrives as an ephemeral message.

Modes:
- on: the hook adds the STE rules to every prompt.
- strict: "on" plus a lint gate. A reply with STE violations goes back to you for a rewrite.
- off: the hooks are silent.

Scopes:
- `/ste <mode>` writes the global flag. It applies in every repo.
- `/ste project <mode>` writes `.claude/ste-mode` in the current repo. It overrides the global flag.
- `/ste project clear` removes the repo file.

Settings (the strict-mode lint gate):
- `/ste config` prints every setting with its value and its source (env | project | global | default).
- `/ste set <key> <value>` writes the global config file.
- `/ste project set <key> <value>` writes `.claude/ste-config.json` in the current repo.
- `/ste unset <key>` and `/ste project unset <key>` remove one key from that file.
- Keys: `min-words` (integer >= 1, default 40), `min-total` (integer >= 1, default 2), `max-per-100w` (number >= 0, default 1.0), `lint-type` (`descriptive` or `procedural`, default descriptive).
- Precedence per key: environment variable, then project file, then global file, then the default.
- For these commands, reply with the STE CONFIG table from the context above in a code block, plus the one short line the hook asks for.

Uninstall:
- `/ste uninstall` removes what the hook set wrote: the status line badge, the mode flags, the score file, and the config files. The hook prints one line per action.
- The plugin itself stays installed until the user runs the uninstall command that the hook prints last.
- Reply with the printed lines and nothing else. Do not run tools.
