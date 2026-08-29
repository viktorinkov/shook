---
name: ste
description: Toggle Simple English (ASD-STE100) mode. Usage - /ste on | strict | off | status | project on|strict|off|clear
argument-hint: on | strict | off | status | project <mode>
---

A hook read this command before you saw it. The hook updated the mode file and printed the new mode and its source as context above.

Reply with one short line that confirms the mode and the source, for example: "STE mode: strict (project)."

Do not run tools. Do not do other work in this reply.

On GitHub Copilot CLI the hook output is dropped. If no "STE MODE IS NOW" line is above, reply: "STE mode saved. It applies at the next session start." On Codex the command is typed as `$ste on`. The Codex skill picker inserts it as `$simple-english-hook:ste`. The hook accepts both forms. On Antigravity CLI the hook reads the command from the transcript, and the "STE MODE IS NOW" line arrives as an ephemeral message.

Modes:
- on: the hook adds the STE rules to every prompt.
- strict: "on" plus a lint gate. A reply with STE violations goes back to you for a rewrite.
- off: the hooks are silent.

Scopes:
- `/ste <mode>` writes the global flag. It applies in every repo.
- `/ste project <mode>` writes `.claude/ste-mode` in the current repo. It overrides the global flag.
- `/ste project clear` removes the repo file.
