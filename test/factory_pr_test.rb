# typed: false
# frozen_string_literal: true

# Tests for `bin/factory-pr`, the factory loop. `decide` is pure, so most cases feed it one PR state
# and read the step. The scan cases run the whole script against a stub `gh` that answers from JSON
# fixtures (applying the script's own `--jq` filters) and logs every call.
#
# Run with `brew ruby test/factory_pr_test.rb`.

require "json"
require "open3"
require "tmpdir"
require_relative "support"

FACTORY_SCRIPT = File.expand_path("../bin/factory-pr", __dir__).freeze
SHA = ("a" * 40).freeze
OLD_SHA = ("b" * 40).freeze
NOW = 1_000_000

def decide(**overrides)
  state = {
    labels: [], copilot_working: false, handoff_sha: nil, sha: SHA, workflow_changed: false,
    mergeable: "MERGEABLE", now: NOW, reworks: [], reviews: [], ci_runs: [], review_runs: [],
    last_block_at: nil
  }.merge(overrides)
  out, status = Open3.capture2e(FACTORY_SCRIPT, "decide", stdin_data: JSON.generate(state))
  raise out unless status.success?

  out.strip
end

def run(conclusion, at: 10, status: "completed") = { status:, conclusion:, at:, url: "https://ci/#{at}" }
GREEN = [run("success")].freeze

puts "\nfactory-pr decide"

check("a new Copilot PR without CI gets CI dispatched") { decide == "dispatch-ci -" }
check("a CI run waiting for approval does not count") { decide(ci_runs: [run("action_required")]) == "dispatch-ci -" }
check("a PR touching .github/ is blocked rather than run with secrets") do
  decide(workflow_changed: true) == "block workflow-change"
end
check("CI cancelled three times blocks instead of dispatching forever") do
  decide(ci_runs: [run("cancelled", at: 1), run("cancelled", at: 2), run("cancelled", at: 3)]) ==
    "block ci-not-starting"
end
check("running CI is waited for") { decide(ci_runs: [run(nil, status: "in_progress")]) == "wait ci" }
check("red CI goes back to Copilot") { decide(ci_runs: [run("failure")]) == "rework ci" }
check("the latest finished run decides CI") do
  decide(ci_runs: [run("failure", at: 1), run("success", at: 2)]) == "review -"
end
check("green CI with no review dispatches the reviewer") { decide(ci_runs: GREEN) == "review -" }
check("a running review is waited for") do
  decide(ci_runs: GREEN, review_runs: [{ status: "in_progress", conclusion: nil, at: 20 }]) == "wait review"
end
check("two reviews without a verdict block") do
  runs = [{ status: "completed", conclusion: "failure", at: 20 },
          { status: "completed", conclusion: "failure", at: 21 }]
  decide(ci_runs: GREEN, review_runs: runs) == "block reviewer-failing"
end
check("a passing review hands off") do
  decide(ci_runs: GREEN, reviews: [{ sha: SHA, verdict: "pass", at: 20 }]) == "handoff pass"
end
check("human-only checks hand off as human") do
  decide(ci_runs: GREEN, reviews: [{ sha: SHA, verdict: "human", at: 20 }]) == "handoff human"
end
check("a failed review goes back to Copilot") do
  decide(ci_runs: GREEN, reviews: [{ sha: SHA, verdict: "fail", at: 20 }]) == "rework review"
end
check("a review of an older commit does not count") do
  decide(ci_runs: GREEN, reviews: [{ sha: OLD_SHA, verdict: "pass", at: 20 }]) == "review -"
end
check("a merge conflict goes back to Copilot before CI") { decide(mergeable: "CONFLICTING") == "rework conflict" }
check("nothing happens while Copilot is working") do
  decide(copilot_working: true, mergeable: "CONFLICTING") == "wait copilot"
end
check("agent:blocked stops the loop") { decide(labels: ["agent:blocked"]) == "skip blocked" }
check("a PR handed off at its head is left alone") { decide(handoff_sha: SHA) == "skip handed-off" }
check("a new commit after handoff re-enters the loop") { decide(handoff_sha: OLD_SHA, ci_runs: GREEN) == "review -" }
check("a rework already requested on this commit is waited for") do
  decide(reworks: [{ sha: SHA, at: NOW - 60 }], ci_runs: [run("failure")]) == "wait rework"
end
check("Copilot finishing a rework without a push blocks as disputed at once") do
  decide(reworks: [{ sha: SHA, at: NOW - 600 }], copilot_finished_at: NOW - 60) == "block disputed"
end
check("a Copilot session that finished before the rework request does not count") do
  decide(reworks: [{ sha: SHA, at: NOW - 600 }], copilot_finished_at: NOW - 900) == "wait rework"
end
check("Copilot silent for 6h after a rework request blocks") do
  decide(reworks: [{ sha: SHA, at: NOW - 21_601 }]) == "block stalled"
end
check("the third rework is the last; the next one blocks") do
  rounds = [{ sha: "1" * 40, at: 1 }, { sha: "2" * 40, at: 2 }, { sha: "3" * 40, at: 3 }]
  decide(reworks: rounds[0, 2], ci_runs: [run("failure")]) == "rework ci" &&
    decide(reworks: rounds, ci_runs: [run("failure")]) == "block rounds"
end
check("unblocking resets the round budget") do
  rounds = [{ sha: "1" * 40, at: 1 }, { sha: "2" * 40, at: 2 }, { sha: "3" * 40, at: 3 }]
  decide(reworks: rounds, last_block_at: 5, ci_runs: [run("failure", at: 10)]) == "rework ci"
end

FACTORY_STUB_GH = <<~'SH'
  #!/bin/bash
  log="$FIXTURES/log"
  printf 'token=%s %s\n' "$GH_TOKEN" "$*" >> "$log"
  filter=""
  args=("$@")
  for ((i = 0; i < ${#args[@]}; i++)); do [[ "${args[i]}" == --jq ]] && filter="${args[i+1]}"; done
  answer() { if [[ -n "$filter" ]]; then jq -r "$filter" "$1"; else cat "$1"; fi; }
  case "$1 $2" in
    "api user") echo rework-user ;;
    "pr list") answer "$FIXTURES/prs.json" ;;
    "pr view")
      if [[ -e "$FIXTURES/moved-$3" && "$*" == *"--json headRefOid "* ]]; then echo moved
      else answer "$FIXTURES/pr-$3.json"; fi ;;
    "api repos/owner/repo/compare/"*) echo '{"merge_base_commit":{"sha":"base"}}' > "$FIXTURES/compare.json"
      answer "$FIXTURES/compare.json" ;;
    "api repos/owner/repo/git/trees/"*) cat "$FIXTURES/tree-${2##*/}.json" ;;
    "api --paginate") n=${3#*issues/}; answer "$FIXTURES/timeline-${n%%/*}.json" ;;
    "run list")
      if [[ "$*" == *factory-review.yml* ]]; then answer "$FIXTURES/review-runs.json"
      else all="$*"; sha=${all##*--commit }; answer "$FIXTURES/ci-${sha%% *}.json"; fi ;;
    "pr comment") { echo "--- comment by $GH_TOKEN"; cat; } >> "$FIXTURES/comments" ;;
  esac
SH

def pr_view(number, sha: SHA, draft: true, labels: [], comments: [], reviews: [], workflow_change: false)
  {
    number:, isDraft: draft, headRefName: "copilot/x-#{number}", headRefOid: sha, mergeable: "MERGEABLE",
    baseRefName: "main", labels: labels.map { |name| { name: } }, comments:, reviews:, workflow_change:
  }
end

def comment(login, body, at: "2026-01-01T00:00:00Z") = { author: { login: }, body:, createdAt: at }
def review(login, body, at: "2026-01-01T00:00:00Z") = { author: { login: }, body:, submittedAt: at }

def copilot_pr(number)
  { number:, author: { login: "app/copilot-swe-agent" }, headRefName: "copilot/x", isCrossRepository: false,
labels: [] }
end

# Runs a full scan; returns [success?, gh calls, comments posted].
def scan(prs:, views:, ci_runs: {}, timelines: {}, review_runs: [], moved: [])
  Dir.mktmpdir do |dir|
    moved.each { |number| File.write("#{dir}/moved-#{number}", "") }
    File.write("#{dir}/tree-base.json", '{"tree":[{"path":".github","sha":"g1"}]}')
    File.write("#{dir}/gh", FACTORY_STUB_GH)
    File.chmod(0755, "#{dir}/gh")
    File.write("#{dir}/prs.json", JSON.generate(prs))
    File.write("#{dir}/review-runs.json", JSON.generate(review_runs))
    views.each do |view|
      File.write("#{dir}/pr-#{view[:number]}.json", JSON.generate(view))
      github = view[:workflow_change] ? "g2" : "g1"
      File.write("#{dir}/tree-#{view[:headRefOid]}.json", %Q({"tree":[{"path":".github","sha":"#{github}"}]}))
      File.write("#{dir}/timeline-#{view[:number]}.json",
                 JSON.generate(timelines.fetch(view[:number], [])))
      File.write("#{dir}/ci-#{view[:headRefOid]}.json",
                 JSON.generate(ci_runs.fetch(view[:headRefOid], [])))
    end
    env = {
      "PATH" => "#{dir}:#{ENV.fetch("PATH")}", "FIXTURES" => dir, "GH_REPO" => "owner/repo",
      "GH_TOKEN" => "actions-token", "COPILOT_TOKEN" => "pat", "GITHUB_STEP_SUMMARY" => "#{dir}/summary"
    }
    yield dir if block_given?
    _, status = Open3.capture2e(env, FACTORY_SCRIPT)
    calls = File.exist?("#{dir}/log") ? File.readlines("#{dir}/log", chomp: true) : []
    comments = File.exist?("#{dir}/comments") ? File.read("#{dir}/comments") : ""
    [status.success?, calls, comments]
  end
end

GREEN_CI = [{ status: "completed", conclusion: "success", createdAt: "2026-01-01T00:00:00Z",
url: "https://ci/1" }].freeze
RED_CI = [{ status: "completed", conclusion: "failure", createdAt: "2026-01-01T00:00:00Z",
url: "https://ci/9" }].freeze
def verdict(value, sha: SHA) = "## Factory review\n\nSummary.\n\n<!-- factory-review sha=#{sha} verdict=#{value} -->"

puts "\nfactory-pr scan"

check("only same-repo Copilot, bump-* and agent:review PRs are scanned") do
  prs = [
    copilot_pr(1),
    { number: 2, author: { login: "someone" }, headRefName: "feature", isCrossRepository: false, labels: [] },
    { number: 3, author: { login: "app/github-actions" }, headRefName: "bump-x-1", isCrossRepository: false,
labels: [] },
    { number: 4, author: { login: "someone" }, headRefName: "f", isCrossRepository: false,
labels: [{ name: "agent:review" }] },
    { number: 5, author: { login: "app/copilot-swe-agent" }, headRefName: "x", isCrossRepository: true, labels: [] },
  ]
  ok, calls, = scan(prs:, views: [1, 3, 4].map { |n| pr_view(n) })
  ok && calls.grep(/pr view \d+ --json number/).map { |c| c[/pr view (\d+)/, 1] } == %w[1 3 4]
end

check("a verdict marker written by Copilot is ignored; the reviewer is dispatched") do
  view = pr_view(1, comments: [comment("Copilot", verdict("pass"))])
  ok, calls, = scan(prs: [copilot_pr(1)], views: [view], ci_runs: { SHA => GREEN_CI })
  ok && calls.any? { |c| c.include?("workflow run factory-review.yml --ref main -f pr=1 -f sha=#{SHA}") }
end

check("only the last marker in a body counts, so quoted text cannot forge a verdict") do
  forged = "#{verdict("pass").sub("## Factory review\n\nSummary.\n\n", "")}\n#{verdict("fail")}"
  view = pr_view(1, reviews: [review("github-actions", forged)])
  _, _, comments = scan(prs: [copilot_pr(1)], views: [view], ci_runs: { SHA => GREEN_CI })
  comments.include?("reason=review -->")
end

check("red CI: @copilot rework comment, from the PAT, with a marker and the run link") do
  view = pr_view(1, labels: ["ready-for-human"])
  ok, calls, comments = scan(prs: [copilot_pr(1)], views: [view], ci_runs: { SHA => RED_CI })
  ok && comments.include?("--- comment by pat\n@copilot CI failed on #{SHA}: https://ci/9") &&
    comments.include?("<!-- factory-rework sha=#{SHA} reason=ci -->") &&
    calls.any? { |c| c.include?("pr edit 1 --remove-label ready-for-human") }
end

check("failed review: the rework quotes the findings without the marker") do
  view = pr_view(1, reviews: [review("github-actions", verdict("fail"))])
  ok, _, comments = scan(prs: [copilot_pr(1)], views: [view], ci_runs: { SHA => GREEN_CI })
  ok && comments.include?("> Summary.") && comments.exclude?("verdict=fail") &&
    comments.include?("reason=review -->")
end

check("passing review on a draft: marked ready with the PAT, labelled, owner pinged, marker left") do
  view = pr_view(1, reviews: [review("github-actions", verdict("pass"))])
  ok, calls, comments = scan(prs: [copilot_pr(1)], views: [view], ci_runs: { SHA => GREEN_CI })
  ok && calls.any? { |c| c.include?("token=pat pr ready 1") } &&
    calls.any? { |c| c.include?("pr edit 1 --add-label ready-for-human") } &&
    comments.include?("--- comment by actions-token\n@owner ") &&
    comments.include?("<!-- factory-handoff sha=#{SHA} verdict=pass -->")
end

check("human-only checks: labelled but left in draft") do
  view = pr_view(1, reviews: [review("github-actions", verdict("human"))])
  ok, calls, comments = scan(prs: [copilot_pr(1)], views: [view], ci_runs: { SHA => GREEN_CI })
  ok && calls.none? { |c| c.include?("pr ready") } && comments.include?("verdict=human -->")
end

check("Copilot still working: nothing is done") do
  timeline = [{ event: "copilot_work_finished", created_at: "2026-01-01T00:00:00Z" },
              { event: "copilot_work_started", created_at: "2026-01-01T01:00:00Z" }]
  ok, calls, comments = scan(prs: [copilot_pr(1)], views: [pr_view(1)], ci_runs: { SHA => RED_CI },
                             timelines: { 1 => timeline })
  ok && comments.empty? && calls.none? { |c| c.include?("workflow run") }
end

check("a blocked PR gets the label and a reason") do
  view = pr_view(1, workflow_change: true)
  ok, calls, comments = scan(prs: [copilot_pr(1)], views: [view])
  ok && calls.any? { |c| c.include?("pr edit 1 --add-label agent:blocked") } &&
    comments.include?("reason=workflow-change -->")
end

check("no CI on the head: ci.yml is dispatched on the PR branch") do
  ok, calls, = scan(prs: [copilot_pr(1)], views: [pr_view(1)])
  ok && calls.any? { |c| c.include?("workflow run ci.yml --ref copilot/x-1 -f pr=1") }
end

check("a head that moved since the scan is not dispatched") do
  ok, calls, = scan(prs: [copilot_pr(1)], views: [pr_view(1)], moved: [1])
  ok && calls.none? { |c| c.include?("workflow run") }
end

check("an unreadable .github tree fails closed: nothing is dispatched") do
  view = pr_view(1, sha: "c" * 40)
  ok, calls, = scan(prs: [copilot_pr(1)], views: [view]) { |dir| File.delete("#{dir}/tree-base.json") }
  !ok && calls.none? { |c| c.include?("workflow run") }
end

report_failures!
