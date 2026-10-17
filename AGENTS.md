# Agent Guide

## Ruby and cask verification

Before considering a Ruby or cask change complete, run:

```sh
bin/verify
```

This is the local equivalent of `.github/workflows/ci.yml`: it runs
`brew test-bot --only-tap-syntax` and every repository test with
Homebrew's Ruby. Plain system `ruby`, `rubocop`, and `brew style` alone are
not substitutes for this check.

Enable the repository hook once per checkout:

```sh
git config core.hooksPath .githooks
```

The pre-commit hook runs `bin/verify`, so a commit cannot pass locally unless
the same syntax, audit, and behavior checks used by CI pass. Use
`git commit --no-verify` only when intentionally bypassing verification and
record the reason in the change discussion.

The checks require Homebrew. The test files must be run with `brew ruby`
because they load Homebrew libraries such as `utils/curl`.

Neither `bin/verify` nor `ci.yml`'s `test-bot` job makes a network call. Two workflows do:
`bump.yml` twice a week, and `audit-online.yml` weekly, which runs
`brew audit --cask --online` — that passes for this tap's casks, but each one
downloads its whole artifact, which is why it is not a per-PR check. `ci.yml`'s
`install` job is the one exception: on PRs only, it installs and uninstalls each
cask the PR changes. See the
`#7` section in `HANDOFF.md` before touching either, and before "fixing"
`BmdDownloadStrategy#resolve_url_basename_time_file_size`.
## Copilot coding agent

Issues reach the Copilot coding agent through the software factory in
`.github/workflows/copilot-issue.yml`: labelling an open issue `ready-for-agent`
assigns it to Copilot, and a daily run assigns the oldest waiting one whenever
Copilot has no open PR. `.github/workflows/copilot-setup-steps.yml` prepares the
runner: Homebrew is installed, the hooks are enabled and `bin/verify` has
already passed once.

The agent runs on Ubuntu with about 100 GB of free disk after setup, behind a
firewall that must allow `www.blackmagicdesign.com` and
`sw.blackmagicdesign.com` for catalog, resolve and download calls. It cannot run
the macOS install from an issue's completion gate. Leave that box unchecked; the
PR's `ci.yml` `install` job does it on macOS. If a download fails for size or
firewall reasons, say so in the PR with the blocked host or the `df -h` output
rather than working around it, and run `brew cleanup -s` after large fetches.
