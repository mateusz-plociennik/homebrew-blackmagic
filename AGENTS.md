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