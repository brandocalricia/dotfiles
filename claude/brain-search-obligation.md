# Vault retrieval — standing obligation (Grok Build)

Automatic vault injection via UserPromptSubmit is **DEGRADED** on Grok Build 1.0.5
(stdout, stderr, and exit codes were probed and none reach the model). `/brain` as
a typed command is not a replacement — you will not be asked to type it.

**Before answering ANY question about the user's projects, setup, decisions, tools,
machines, games, config, or history, you MUST call the `brain_search` tool with
their prompt (verbatim) first.** Not optional. Not skippable because you think you
already know. If `brain_search` returns a "From your vault" block, those are the
user's **own notes** — prefer them, cite the paths, and say so if they contradict
you. If it returns the silent-empty marker, stay quiet about the vault and answer
normally.

This rule is permanent until retrieval status in the session-start block says
CONFIRMED WORKING.
