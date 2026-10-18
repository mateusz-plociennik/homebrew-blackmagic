---
name: implement
description: "Implement a ready-for-agent issue or approved spec through tests, verification, review and a pull request. Use when assigned a factory ticket."
---

# Implement

1. Read the issue body, comments, parent context and native blockers. Start only
   when blockers are closed and human registration or licence prerequisites
   are satisfied. Reuse an existing implementation PR when one is linked.
2. Implement the ticket's complete vertical slice. Use a failing behaviour test
   first where a testable seam exists, then make it pass with the smallest
   complete change. Run focused tests while iterating.
3. Run the repository's required verification gate from the agent guide before
   completion. Record commands and results. Leave unavailable macOS or human
   checks unchecked, with the exact blocker and next step.
4. Review the connected code and full diff for correctness, regressions and
   acceptance-criteria coverage; fix findings and rerun affected checks.
5. Commit to the assigned working branch and update the implementation PR with
   evidence and remaining gates. Keep the issue open until its completion
   policy is satisfied, including any required parent evidence handoff.

This repository-local workflow adapts the implement approach from
[mattpocock/skills](https://github.com/mattpocock/skills). TDD and review steps
are explicit so the cloud agent does not depend on editor-only slash commands.
