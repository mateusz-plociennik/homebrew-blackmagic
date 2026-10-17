# typed: false
# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
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
    "issue edit") [[ -e "$FIXTURES/assign-fails" ]] && exit 1; true ;;
    *) echo "Unexpected gh call: $*" >&2; exit 1 ;;
  esac
SH

def assign_copilot(labelled: "", issues: [44], busy: 0, state: "OPEN", labels: ["ready-for-agent"],
                   assignee: "mateusz-plociennik", references: [[]], timelines: {},
                   api_fails: false, assign_fails: false)
  Dir.mktmpdir do |dir|
    File.write("#{dir}/gh", ASSIGN_STUB_GH)
    File.chmod(0755, "#{dir}/gh")
    File.write("#{dir}/busy", busy.to_s)
    File.write("#{dir}/issues", issues.join("\n"))
    issues.each do |issue|
      File.write("#{dir}/issue-#{issue}", {
        state:, labels: labels.map { |name| { name: } }, assignees: [{ login: assignee }]
      }.to_json)
      File.write("#{dir}/timeline-#{issue}", timelines.fetch(issue, references).map do |refs|
        { data: { repository: { issue: { timelineItems: { nodes: refs } } } } }.to_json
      end.join("\n"))
    end
    File.write("#{dir}/api-fails", "") if api_fails
    File.write("#{dir}/assign-fails", "") if assign_fails
    env = {
      "PATH" => "#{dir}:#{ENV.fetch("PATH")}", "FIXTURES" => dir, "GH_REPO" => "o/r", "GH_TOKEN" => "test",
      "LABELLED_ISSUE" => labelled.to_s, "GITHUB_STEP_SUMMARY" => "#{dir}/summary"
    }
    output, status = Open3.capture2e(env, "bash", ASSIGN_SCRIPT)
    calls = File.readlines("#{dir}/log", chomp: true)
    [status.success?, calls.grep(/^issue edit/).map { |call| call.split[2] }, output]
  end
end

def pr_reference(state, cross_repository: false, body: "Adds casks for #44", closes: false)
  {
    isCrossRepository: cross_repository, willCloseTarget: closes,
    source: { __typename: "PullRequest", number: 75, state:, body: }
  }
end

puts "\nassign-copilot"

check("a human assignee does not block a ready issue") do
  ok, assigned = assign_copilot(references: [[]])
  ok && assigned == ["44"]
end

["OPEN", "MERGED"].each do |state|
  check("a labelled issue mentioned by a #{state.downcase} batch PR is not assigned, even on a later page") do
    ok, assigned, output = assign_copilot(labelled: 44, references: [[], [pr_reference(state)]])
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
    ok, assigned = assign_copilot(labelled: 44, **options)
    ok && assigned.empty?
  end
end

check("a busy Copilot blocks the daily queue") do
  ok, assigned = assign_copilot(busy: 1)
  ok && assigned.empty?
end

check("a failed reference lookup fails closed without assigning") do
  ok, assigned = assign_copilot(labelled: 44, api_fails: true)
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

report_failures!
