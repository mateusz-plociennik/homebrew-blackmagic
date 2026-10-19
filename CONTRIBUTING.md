# Contributing

## Prerequisites

- macOS
- Homebrew

## Configure the checkout

Enable the repository Git hooks one time for each checkout:

```sh
git config core.hooksPath .githooks
```

- The `pre-commit` hook runs `bin/verify`. If a check fails, the commit stops.
- The `pre-push` hook stops a force push to `main`.

## Verify a change

Run this command before you commit a Ruby or cask change:

```sh
bin/verify
```

The script does the same checks as the `test-bot` job in `ci.yml`:

1. It links this checkout as a temporary tap.
2. It runs `brew test-bot --only-tap-syntax` on that tap.
3. It runs all tests in `test/` with `brew ruby`.

Use `brew ruby` for the tests, because they load Homebrew libraries. The script makes no network
requests.

## Add a cask

1. Make the cask file. The script downloads the artifact and examines it:

   ```sh
   brew ruby bin/generate-cask "<Product Name>" [<version>]
   ```

2. Make a record of the installed package receipts:

   ```sh
   pkgutil --pkgs > before
   ```

3. Install and uninstall the cask:

   ```sh
   brew install --cask mateusz-plociennik/blackmagic/<token>
   brew uninstall --cask <token>
   ```

   The casks load `lib/` from the installed tap. Thus, do this work in the tap checkout at
   `$(brew --repo mateusz-plociennik/blackmagic)`.

4. Make a second record and compare the two records:

   ```sh
   pkgutil --pkgs > after
   bin/compare-receipts before after
   ```

   The script fails if a receipt stays after the uninstall, or if the uninstall removes a receipt
   that was there before.

5. Make sure that the uninstall does not remove files that other Blackmagic products share. A
   receipt comparison does not find this problem. Refer to the notes in
   [`blackmagic-davinci-resolve.rb`](Casks/blackmagic-davinci-resolve.rb).

### Uninstall policy

The generated `uninstall` stanza removes only the package receipts. If the product has a vendor
uninstaller, change the stanza:

- Remove the same items as the vendor uninstaller. If the vendor uninstaller is a script, run it
  with `uninstall script:`. If the vendor uninstaller cannot run unattended, copy its steps into
  `launchctl:`, `delete:` and `rmdir:`.
- Keep the receipts correct. Remove a receipt when the uninstall removes its files. Keep a receipt
  when the vendor uninstaller keeps its files.
- Write a note in the cask. The note tells how to change to receipt-only cleanup.

If the uninstall keeps receipts on purpose, add the cask to `SKIP_CASKS` in `ci.yml`.

To list the Blackmagic products that have no cask and no skip reason, run:

```sh
brew ruby bin/generate-cask --report-missing
```

Skip reasons are in [`lib/bmd_skip_list.rb`](lib/bmd_skip_list.rb).

## Design notes

The design notes are comments in the code. Read the comments in [`lib/`](lib) and in the casks
before you change the download, resolve or config logic.

## Workflows

| Workflow | Trigger | Function |
|---|---|---|
| `ci.yml` | Pull request | Runs the `bin/verify` checks. On macOS, installs and uninstalls each cask that the pull request changes. |
| `bump.yml` | Monday and Thursday | Runs `brew bump` and opens a pull request for each new release. Starts `ci.yml` for these pull requests. |
| `audit-online.yml` | Monday | Runs `brew audit --cask --online`. This downloads each full artifact. |
| `copilot-issue.yml` | Issue and pull request events | Assigns `ready-for-agent` issues to the Copilot coding agent. |

To see the result of `bump.yml` without new pull requests, start it manually from the Actions tab
and select **report-only**.

If a bump pull request gets no CI run on each bump run, close the pull request and delete its
branch. The next bump run opens it again from `main`.

## Issues and labels

Work is in GitHub Issues. Each issue shows its blocking issues.

| Label | Meaning |
|---|---|
| `needs-triage` | A maintainer must examine the issue. |
| `needs-info` | The reporter must supply more information. |
| `ready-for-agent` | The issue is fully specified. The Copilot coding agent can do it. |
| `ready-for-human` | A human must do the issue. |
| `backlog` | The issue is blocked or deferred. The Copilot queue ignores it. |
| `wontfix` | No work will occur. |

The Copilot queue runs up to `COPILOT_MAX_PARALLEL` issues at once (set in `copilot-issue.yml`; currently 4):

- It selects the oldest open `ready-for-agent` issues that have no open blockers.
- Each open Copilot pull request and each Copilot assignment with no pull request uses one slot.
  The queue waits while every slot is in use.
- It ignores issues with the `backlog` label, a Copilot assignee, or a linked implementation pull
  request.

Use `ready-for-agent` only for an issue that has no blockers now. To try an issue again, remove
Copilot from the assignees and then assign Copilot again.
