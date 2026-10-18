# Issue tracker: GitHub

Use `gh` (repo inferred from the clone). "Publish to the issue tracker" = create an issue; "fetch the ticket" = read it.

- Create: `gh issue create --title … --body …` (heredoc for multi-line).
- Read: `gh issue view <n> --json number,title,body,labels,comments`.
- List: `gh issue list --state open --json number,title,body,labels,comments` plus `--label` filters.
- Comment / label / close: `gh issue comment`, `gh issue edit --add-label|--remove-label`, `gh issue close --comment`.
- Sub-issue: `gh issue create --parent <p>` or `gh issue edit <p> --add-sub-issue <c>` (gh 2.94+). Fallback: `Part of #<p>` atop the child body.
- Blocking: native dependencies. `gh api --method POST repos/{owner}/{repo}/issues/<child>/dependencies/blocked_by -F issue_id=<db-id>`; db id from `gh api repos/{owner}/{repo}/issues/<n> --jq .id` (not `#n`/`node_id`). Open blockers: `issue_dependencies_summary.blocked_by`. Fallback: `Blocked by: #a, #b` atop the body. Unblocked = all blockers closed.
- `#n` may be a PR: try `gh pr view n`, then `gh issue view n`.

**PRs as a request surface: no.** (`/triage` reads this flag.)

## Wayfinding (`/wayfinder`)

- Map: one issue labelled `wayfinder:map` with Notes / Decisions-so-far / Fog body.
- Child ticket: sub-issue of the map (fallback: task list in the map + `Part of #<map>`), labelled `wayfinder:<research|prototype|grilling|task>`.
- Frontier: open children without open blockers or assignee; first in map order wins.
- Claim: `gh issue edit <n> --add-assignee @me` (first write of the session).
- Resolve: comment the answer, close, then append a gist + link to the map's Decisions-so-far.
