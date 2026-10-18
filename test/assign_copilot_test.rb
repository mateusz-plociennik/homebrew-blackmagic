# typed: false
# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require "yaml"
require_relative "support"

ASSIGN_SCRIPT = File.expand_path("../bin/assign-copilot", __dir__).freeze
ASSIGN_STUB_GH = <<~SH
  #!/bin/bash
  echo "$*" >> "$FIXTURES/log"
  case "$1 $2" in
    "pr list") cat "$FIXTURES/busy" ;;
    "issue list") cat "$FIXTURES/issues" ;;
    "issue view") cat "$FIXTURES/issue-$3" ;;
    "api graphql")
      [[ -e "$FIXTURES/api-fails" ]] && exit 1
      args="$*"; number=${args##*number=}; number=${number%% *}
      cat "$FIXTURES/timeline-$number" ;;
    "api --paginate")
      [[ -e "$FIXTURES/rest-fails" ]] && exit 1
      case "$3" in
        */events?*) cat "$FIXTURES/assignment-events" ;;
        */dependencies/blocked_by*)
          [[ -e "$FIXTURES/dependencies-fail" ]] && exit 1
          cat "$FIXTURES/blockers" ;;
        *issues?*) cat "$FIXTURES/assigned" ;;
        *) echo "Unexpected REST call: $*" >&2; exit 1 ;;
      esac ;;
    "issue edit") [[ -e "$FIXTURES/assign-fails" ]] && exit 1; true ;;
    *) echo "Unexpected gh call: $*" >&2; exit 1 ;;
  esac
SH

def assign_copilot(issues: [44], busy: 0, state: "OPEN", labels: ["ready-for-agent"],
                   assignee: "mateusz-plociennik", references: [[]], timelines: {},
                   assigned: [], blockers: [], blocker_pages: nil,
                   assignment_events: nil,
                   api_fails: false, rest_fails: false, dependencies_fail: false, assign_fails: false)
  Dir.mktmpdir do |dir|
    File.write("#{dir}/gh", ASSIGN_STUB_GH)
    File.chmod(0755, "#{dir}/gh")
    File.write("#{dir}/busy", busy.to_s)
    File.write("#{dir}/issues", issues.join("\n"))
    File.write("#{dir}/assigned", assigned.map do |number|
      { number:, assignees: [{ login: "Copilot" }] }
    end.to_json)
    File.write("#{dir}/assignment-events", (assignment_events || [{
      event: "assigned", created_at: "2026-01-01T00:00:00Z", assignee: { login: "Copilot" }
    }]).to_json)
    File.write("#{dir}/blockers", (blocker_pages || [blockers]).map(&:to_json).join("\n"))
    (issues + assigned).uniq.each do |issue|
      File.write("#{dir}/issue-#{issue}", {
        state:, labels: labels.map { |name| { name: } }, assignees: [{ login: assignee }]
      }.to_json)
      File.write("#{dir}/timeline-#{issue}", timelines.fetch(issue, references).map do |refs|
        { data: { repository: { issue: { timelineItems: { nodes: refs } } } } }.to_json
      end.join("\n"))
    end
    File.write("#{dir}/api-fails", "") if api_fails
    File.write("#{dir}/rest-fails", "") if rest_fails
    File.write("#{dir}/dependencies-fail", "") if dependencies_fail
    File.write("#{dir}/assign-fails", "") if assign_fails
    env = {
      "PATH" => "#{dir}:#{ENV.fetch("PATH")}", "FIXTURES" => dir, "GH_REPO" => "o/r", "GH_TOKEN" => "test",
      "GITHUB_STEP_SUMMARY" => "#{dir}/summary"
    }
    output, status = Open3.capture2e(env, "bash", ASSIGN_SCRIPT)
    calls = File.readlines("#{dir}/log", chomp: true)
    [status.success?, calls.grep(/^issue edit/).map { |call| call.split[2] }, output]
  end
end

def pr_reference(state, cross_repository: false, body: "Adds casks for #44", closes: false,
                 created_at: "2026-02-01T00:00:00Z")
  {
    isCrossRepository: cross_repository, willCloseTarget: closes,
    source: { __typename: "PullRequest", number: 75, state:, body:, createdAt: created_at }
  }
end

puts "\nassign-copilot"

check("a human assignee does not block a ready issue") do
  ok, assigned = assign_copilot(references: [[]])
  ok && assigned == ["44"]
end

["OPEN", "MERGED"].each do |state|
  check("a labelled issue mentioned by a #{state.downcase} batch PR is not assigned, even on a later page") do
    ok, assigned, output = assign_copilot(references: [[], [pr_reference(state)]])
    ok && assigned.empty? && output.include?("#75")
  end
end

check("the queue continues past covered issues without assigning them") do
  ok, assigned = assign_copilot(issues: [44, 62], timelines: { 44 => [[pr_reference("OPEN")]] })
  ok && assigned == ["62"]
end

check("closed unmerged and cross-repository PRs do not block an issue") do
  ok, assigned = assign_copilot(references: [[pr_reference("CLOSED"), pr_reference("OPEN", cross_repository: true)]])
  ok && assigned == ["44"]
end

check("incidental references from PR comments do not block unrelated work") do
  ok, assigned = assign_copilot(references: [[pr_reference("MERGED", body: "Configure the software factory")]])
  ok && assigned == ["44"]
end

check("similarly numbered issues and references to other repositories do not block work") do
  ok, assigned = assign_copilot(references: [[pr_reference("OPEN", body: "Fixes #440 and other/repo#44")]])
  ok && assigned == ["44"]
end

["Adds o/r#44", "Adds https://github.com/o/r/issues/44"].each do |body|
  check("qualified PR-body references also block duplicate work: #{body}") do
    ok, assigned = assign_copilot(references: [[pr_reference("OPEN", body:)]])
    ok && assigned.empty?
  end
end

check("an explicit closing link blocks work even without an issue reference in the PR body") do
  ok, assigned = assign_copilot(references: [[pr_reference("OPEN", body: "Implement cask", closes: true)]])
  ok && assigned.empty?
end

[
  { state: "CLOSED" }, { labels: [] }, { labels: ["ready-for-agent", "backlog"] },
  { assignee: "Copilot" }, { assignee: "copilot-swe-agent" }, { assignee: "copilot-swe-agent[bot]" }
].each do |options|
  check("a stale label event cannot assign an ineligible issue: #{options}") do
    ok, assigned = assign_copilot(**options)
    ok && assigned.empty?
  end
end

check("a busy Copilot blocks every queue trigger") do
  ok, assigned = assign_copilot(busy: 1)
  ok && assigned.empty?
end

check("a failed reference lookup fails closed without assigning") do
  ok, assigned = assign_copilot(api_fails: true)
  !ok && assigned.empty?
end

check("a failed assignment fails the run") do
  ok, = assign_copilot(references: [[]], assign_fails: true)
  !ok
end

check("an empty queue is a successful no-op") do
  ok, assigned = assign_copilot(issues: [])
  ok && assigned.empty?
end

check("an assigned issue reserves the slot before Copilot opens its PR") do
  ok, assigned, output = assign_copilot(assigned: [62])
  ok && assigned.empty? && output.include?("has not opened a PR")
end

check("an old closed PR cannot release a retried assignment's reservation") do
  ok, assigned, output = assign_copilot(assigned: [62], timelines: {
    62 => [[pr_reference("CLOSED", body: "Fixes #62", created_at: "2025-12-01T00:00:00Z")]],
  })
  ok && assigned.empty? && output.include?("has not opened a PR")
end

check("the latest Copilot assignment, not a previous assignment, defines the reservation") do
  events = [
    { event: "assigned", created_at: "2025-01-01T00:00:00Z", assignee: { login: "Copilot" } },
    { event: "assigned", created_at: "2026-03-01T00:00:00Z", assignee: { login: "Copilot" } },
    { event: "assigned", created_at: "2026-04-01T00:00:00Z", assignee: { login: "human" } },
  ]
  ok, assigned = assign_copilot(assigned: [62], assignment_events: events, timelines: {
    62 => [[pr_reference("CLOSED", body: "Fixes #62")]],
  })
  ok && assigned.empty?
end

check("an assigned issue with no visible assignment event fails closed") do
  ok, assigned = assign_copilot(assigned: [62], assignment_events: [])
  !ok && assigned.empty?
end

["CLOSED", "MERGED"].each do |state|
  check("an assigned issue with a #{state.downcase} PR does not stop the next ticket") do
    ok, assigned = assign_copilot(assigned: [62], timelines: {
      62 => [[pr_reference(state, body: "Fixes #62")]],
    })
    ok && assigned == ["44"]
  end
end

check("an unresolved native blocker prevents assignment") do
  ok, assigned, output = assign_copilot(blockers: [{ number: 12, state: "open" }])
  ok && assigned.empty? && output.include?("waiting for blocker(s): #12")
end

check("closed native blockers allow assignment") do
  ok, assigned = assign_copilot(blockers: [{ number: 12, state: "closed" }])
  ok && assigned == ["44"]
end

check("all pages of native blockers are checked") do
  ok, assigned = assign_copilot(blocker_pages: [[], [{ number: 12, state: "open" }]])
  ok && assigned.empty?
end

check("a failed dependency lookup fails closed") do
  ok, assigned = assign_copilot(dependencies_fail: true)
  !ok && assigned.empty?
end

check("a failed native dependency or reservation lookup fails without assigning") do
  ok, assigned = assign_copilot(rest_fails: true)
  !ok && assigned.empty?
end

check("the workflow wakes a shared serial queue on readiness and closure without cron") do
  workflow = YAML.load_file(File.expand_path("../.github/workflows/copilot-issue.yml", __dir__))
  events = workflow.fetch("on") { workflow.fetch(true) }
  events.fetch("issues").fetch("types").include?("labeled") &&
    events.fetch("issues").fetch("types").include?("closed") &&
    events.fetch("pull_request_target").fetch("types") == ["closed"] &&
    !events.key?("schedule") &&
    workflow.fetch("concurrency").fetch("group").exclude?("issue.number") &&
    !workflow.fetch("jobs").fetch("assign").fetch("steps").last.fetch("env").key?("LABELLED_ISSUE")
end

report_failures!
