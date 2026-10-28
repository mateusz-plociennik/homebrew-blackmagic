# AGENTS.md

Human docs: `README.md` (users), `CONTRIBUTING.md` (workflows, labels, adding casks). Design rationale lives in code comments in `lib/` and `Casks/`; read them before changing behaviour.

## Verify

- Done = `bin/verify` passes (CI's `test-bot` job + all tests; offline). Plain `ruby`/`rubocop`/`brew style` are not substitutes; tests need `brew ruby`.
- Hooks: `git config core.hooksPath .githooks`. `--no-verify` only deliberately, with the reason in the PR.
- Network: only `bump.yml`, `audit-online.yml` (downloads full artifacts) and `ci.yml`'s PR `install` job. Keep it that way.
- `BmdDownloadStrategy#resolve_url_basename_time_file_size` is load-bearing; read its comment before touching it.

## Gotchas

- Registration details: ask the user; never commit them.
- Fetch `blackmagicdesign.com` with `curl`; WebFetch fails there.
- Changes to `lib/` strategy, resolver or config handle PII and a remote-supplied URL: run code-review and security-review.

## Copilot coding agent

- Assigned issue or approved spec: follow `.github/skills/implement/SKILL.md`.
- Runner: Ubuntu, ~100 GB free, setup already ran `bin/verify`. Firewall allows `www.blackmagicdesign.com`, `sw.blackmagicdesign.com`.
- macOS install gates: leave unchecked; PR `ci.yml` `install` job covers them.
- Blocked download (size/firewall): report host or `df -h` in the PR; no workarounds. `brew cleanup -s` after large fetches.
- Session stops before a PR: remove the ready label and Copilot assignee to free the queue.
- After your PR: the factory loop (`bin/factory-pr`) runs CI and a separate reviewer, and sends you `@copilot` rework comments. Fix each finding or reply why it is wrong. Leave the PR in draft; the loop hands it to a human. Never write `<!-- factory-` markers.

## Agent skills

- Issue tracker: GitHub Issues via `gh`. See `docs/agents/issue-tracker.md`.
- Triage labels: `docs/agents/triage-labels.md`.
- Domain docs: `docs/agents/domain.md`.
