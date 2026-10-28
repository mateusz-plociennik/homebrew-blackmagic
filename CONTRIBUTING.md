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
| `bump.yml` | Monday and Thursday | Runs `brew bump` for each cask and opens a pull request for each new release. Starts `ci.yml` for these pull requests. A release that needs registration gets a `Manual bump:` issue instead. |
| `audit-online.yml` | Monday | Runs `brew audit --cask --online`. This downloads each full artifact. |
| `copilot-issue.yml` | Issue and pull request events | Assigns `ready-for-agent` issues to the Copilot coding agent. |
| `factory-pr.yml` | Every 10 minutes, CI and review completions, pull request events | Moves each factory pull request one step through the loop below. |
| `factory-review.yml` | Started by `factory-pr.yml` | The cold reviewer: Copilot CLI reviews one commit and posts a comment-only review. |

A failing scheduled `bump.yml` or `audit-online.yml` run opens a `Scheduled run failing:` issue, comments
on it at each further failure, and closes it at the next success.

To see the result of `bump.yml` without new pull requests, start it manually from the Actions tab
and select **report-only**.

If a bump pull request gets no CI run on each bump run, close the pull request and delete its
branch. The next bump run opens it again from `main`.

## Factory loop

`bin/factory-pr` takes each open pull request from Copilot, from `bump.yml`, or with the `agent:review`
label, and moves it one step on each scan until a human can merge it:

1. It waits while Copilot is working, CI is running, or a review is running.
2. When the head commit has no CI run, it starts `ci.yml`. The `pull_request` run of a Copilot or bot
   pull request waits for approval; a started run does not. A pull request that changes `.github/` gets
   `agent:blocked` instead, because a started run would execute the branch's workflow files with this
   repository's secrets. Approve its CI run by hand, then remove the label.
3. When CI fails, the branch conflicts, or the review finds defects, it posts an `@copilot` comment
   with the reason. Copilot pushes a fix, and the loop starts again on the new commit.
4. When CI passes, `factory-review.yml` reviews the commit. The reviewer can only read files: it has
   no shell, no network and no write token. It never approves.
5. When the review passes, the loop marks the pull request ready, adds `ready-for-human`, and mentions
   the owner. When only human checks remain, it adds `ready-for-human` and leaves the pull request in
   draft. You merge.
6. After 3 rework rounds, or 6 hours without a Copilot push, it adds `agent:blocked` with the reason.
   Remove the label to resume with 3 new rounds.

The loop never approves or merges. To see the next step for each pull request without acting, run
`GH_REPO=mateusz-plociennik/homebrew-blackmagic bin/factory-pr --dry-run`.

Secrets:

- `COPILOT_ASSIGN_TOKEN`: a PAT of a Copilot-licensed user with write access. It assigns issues and
  posts the `@copilot` comments. Copilot ignores comments from `GITHUB_TOKEN`.
- `COPILOT_REVIEW_TOKEN`: a fine-grained PAT with only the **Copilot Requests** permission and no
  repository access. Only the review step can read it.

## Issues and labels

Work is in GitHub Issues. Each issue shows its blocking issues.

| Label | Meaning |
|---|---|
| `needs-triage` | A maintainer must examine the issue. |
| `needs-info` | The reporter must supply more information. |
| `ready-for-agent` | The issue is fully specified. The Copilot coding agent can do it. |
| `ready-for-human` | A human must do the issue. |
| `backlog` | The issue is blocked or deferred. The Copilot queue ignores it. |
| `ready-for-human` (pull request) | CI and the review are done. A human merges. |
| `agent:blocked` (pull request) | The factory loop stopped. A comment gives the reason. Remove the label to resume. |
| `agent:review` (pull request) | Puts a human pull request through the factory loop. |
| `wontfix` | No work will occur. |

The Copilot queue assigns every eligible issue at once, oldest first:

- It selects open `ready-for-agent` issues that have no open blockers. There is no concurrency limit.
- It ignores issues with the `backlog` label, a Copilot assignee, or a linked implementation pull
  request.

Use `ready-for-agent` only for an issue that has no blockers now. To try an issue again, remove
Copilot from the assignees and then assign Copilot again.
