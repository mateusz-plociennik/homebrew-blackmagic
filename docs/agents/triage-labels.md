# Triage Labels

Role names map 1:1 to labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`.

Extra: `backlog` = blocked or deferred; keeps the issue out of the Copilot queue. Use `ready-for-agent` only when the issue is unblocked now.

PR labels (factory loop, `bin/factory-pr`): `ready-for-human` = CI and the cold review are done, a human merges; `agent:blocked` = the loop stopped, reason in a PR comment, remove to resume; `agent:review` = put a human PR through the loop.
