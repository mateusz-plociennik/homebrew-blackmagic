# Factory health — 2026-11-14

## 2026-11-14: baseline observations

Code snapshot: `mateusz-plociennik/homebrew-blackmagic@58ec416d9621e23a4555ede4beed536b2eea5574`,
[`bin/factory-pr`](https://github.com/mateusz-plociennik/homebrew-blackmagic/blob/58ec416d9621e23a4555ede4beed536b2eea5574/bin/factory-pr)
and `test/cask_uninstall_test.rb`.

- `brew ruby test/cask_uninstall_test.rb` reproduced `CaskUnavailableError`:
  the loader treated source text as a cask name. Interpreter: Homebrew Ruby
  4.0.9; Homebrew `7.0.13-128-gfc51ba6b2f`. No cask install was attempted.
- [PR #109](https://github.com/mateusz-plociennik/homebrew-blackmagic/pull/109)
  had a generic start at `2026-11-05T08:28:44Z`, attributed by the timeline API
  to App `copilot-pull-request-reviewer`.
  [Run 41994730666](https://github.com/mateusz-plociennik/homebrew-blackmagic/actions/runs/41994730666)
  was completed successfully at `2026-11-05T08:34:31Z`; its path was
  `dynamic/agents/copilot-pull-request-reviewer` and its PR association was #109.
  The baseline scanner instead waited on the undifferentiated timeline start.
- Read-only timeline evidence for
  [PR #86](https://github.com/mateusz-plociennik/homebrew-blackmagic/pull/86)
  identified coding App `copilot-swe-agent`. Dynamic-run API evidence included
  [run 40794600605](https://github.com/mateusz-plociennik/homebrew-blackmagic/actions/runs/40794600605),
  path `dynamic/copilot-swe-agent/copilot`, associated with #86.
- Discovery recorded a same-head `human` handoff on non-draft
  [PR #119](https://github.com/mateusz-plociennik/homebrew-blackmagic/pull/119).
  In the baseline code, human handoff omitted draft conversion and an existing
  same-head handoff skipped all subsequent reconciliation.

## 2026-11-14: local correction, not yet deployed

Supersedes the baseline code behavior above **only on the implementation
branch**, at
`mateusz-plociennik/homebrew-blackmagic@b4cef047f94758a528dfd023825d42550eba5c74`
([code](https://github.com/mateusz-plociennik/homebrew-blackmagic/blob/b4cef047f94758a528dfd023825d42550eba5c74/bin/factory-pr),
[regressions](https://github.com/mateusz-plociennik/homebrew-blackmagic/blob/b4cef047f94758a528dfd023825d42550eba5c74/test/factory_pr_test.rb)).

- Cask tests loaded local paths with `CaskLoader.from_path`; assertions and
  cask definitions were unchanged.
- Native-review App events and native-review workflow runs were excluded from
  coding activity. Paginated branch-scoped dynamic runs retained active coding
  and unknown active work as waits; API failures failed the PR scan closed.
  No terminal run was guessed to correspond to a timeline start by timestamp.
- Without a confirmed active run, unmatched starts used the existing six-hour
  timeout, or the earlier outstanding rework deadline, then blocked with
  `activity-unknown` rather than dispatching overlapping work. Deliberate
  unblocking acknowledged pre-block starts, not active runs or newer starts.
- Human handoff converted non-drafts before labelling/commenting. Same-head
  existing human handoffs reconciled only draft state, without another marker.
  Conversion failure reported failure without a new success marker; pass
  handoffs retained their prior behavior.
- Seven initial mocked regressions failed before implementation. Focused
  cask/factory tests and required `bin/verify` passed afterward, including the
  enabled commit hook. Tests used local fixtures and mocked `gh`; no workflow
  dispatch or live PR repair was performed. Initial style failures were fixed
  before the passing gate.

## 2026-11-14: rollout gate and limits

Independent review and human acceptance were still pending. Intended next
steps: review the commits, then follow the repository's draft-PR process if
approved. After landing, observe a naturally scheduled scan; do not force one.
Re-read exact-head evidence before any human merge. #119 was not repaired live.

The correction depended on the observed GitHub App/workflow identities and
branch-scoped Actions API. Unknown active runs intentionally remained waits;
API outages intentionally stopped actions. Human unblocking required checking
and resolving any coding session first. No schedules or retry budgets changed.

Evidence context, recorded 2026-11-14: local discovery report
`factory-discovery.md` in session
`ccae7442-96eb-4e17-828c-bafd9832700b/files/`, and the earlier shared-checkout
`docs/agents/factory-state-handoff.md` snapshot (local/untracked, not a published
wiki source). Public run links and immutable code pointers above supply the
reproducible repository evidence; the local reports were not copied wholesale.

## 2026-11-14: independent-review addendum — shared head branches

Independent review found an incomplete activity guard in
`mateusz-plociennik/homebrew-blackmagic@b4cef047f94758a528dfd023825d42550eba5c74`:
PRs targeting different bases could share one same-repository head branch.
Filtering active runs by PR association let one PR request overlapping rework
while coding for the other PR was still mutating their shared branch.

This supersedes the earlier activity-safety claim for that case, without
changing the historical test results above. Correction:
`mateusz-plociennik/homebrew-blackmagic@d696c76379273756b2df8339022ba2a487bc30db`
([code and regression](https://github.com/mateusz-plociennik/homebrew-blackmagic/commit/d696c76379273756b2df8339022ba2a487bc30db)).
The PR-association filter was removed; repository/encoded-branch API scope and
native-review exclusion were retained. Active non-native runs guarded branch
mutation regardless of their associated PR.

A full-scan regression failed before the correction, then passed: both
shared-branch PRs waited while an unrelated branch still requested its own
rework. A second regression retained active-native-review exclusion. Focused
factory tests passed 54 assertions; the enabled `bin/verify` commit hook passed
274 assertions plus the existing offline tap and shell checks. One initial
regexp-style failure was corrected before the passing gate. No live GitHub
mutation, push or PR accompanied this follow-up.
