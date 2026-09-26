# typed: false
# frozen_string_literal: true

# Tests for `bin/dispatch-bump-ci`, bump.yml's CI dispatch step, against a stub `gh` on PATH. The stub
# answers from files in a fixtures directory and logs every call, so each case is: which PRs are open,
# which head commits already have a CI run, which dispatches fail — then read the log.
#
# Run with `brew ruby test/dispatch_bump_ci_test.rb`.

require "open3"
require "tmpdir"
require_relative "support"

DISPATCH_SCRIPT = File.expand_path("../bin/dispatch-bump-ci", __dir__).freeze

STUB_GH = <<~'SH'
  #!/bin/bash
  args="$*"
  echo "$args" >> "$FIXTURES/log"
  case "$1 $2" in
    "pr list") [[ -e "$FIXTURES/pr-list-fails" ]] && exit 1; cat "$FIXTURES/prs" ;;
    "run list") sha=${args##*--commit }; sha=${sha%% *}; [[ -e "$FIXTURES/run-$sha" ]] && echo 1 || echo 0 ;;
    "pr diff") printf '+++ b/Casks/blackmagic-x.rb\n-  version "1.1"\n+  version "1.2"\n' ;;
    "workflow run") [[ -e "$FIXTURES/dispatch-fails-${args##*pr=}" ]] && exit 1; true ;;
    "pr comment") [[ -e "$FIXTURES/comment-fails-$3" ]] && exit 1; true ;;
    "pr view") [[ -e "$FIXTURES/commented-$3" ]] && echo 1 || echo 0 ;;
  esac
SH

# Runs the script against `prs` (lines of "number branch sha"); returns [success?, calls made].
def dispatch(prs, runs: [], failing: [], failing_comments: [], commented: [], pr_list_fails: false)
  Dir.mktmpdir do |dir|
    File.write("#{dir}/gh", STUB_GH)
    File.chmod(0755, "#{dir}/gh")
    File.write("#{dir}/prs", prs.join("\n"))
    runs.each { |sha| File.write("#{dir}/run-#{sha}", "") }
    failing.each { |pr| File.write("#{dir}/dispatch-fails-#{pr}", "") }
    failing_comments.each { |pr| File.write("#{dir}/comment-fails-#{pr}", "") }
    commented.each { |pr| File.write("#{dir}/commented-#{pr}", "") }
    File.write("#{dir}/pr-list-fails", "") if pr_list_fails
    env = { "PATH" => "#{dir}:#{ENV.fetch("PATH")}", "FIXTURES" => dir, "REPO" => "o/r", "TAP" => "o/t" }
    _, status = Open3.capture2e(env, DISPATCH_SCRIPT)
    calls = File.exist?("#{dir}/log") ? File.readlines("#{dir}/log", chomp: true) : []
    [status.success?, calls]
  end
end

def dispatched(calls) = calls.grep(/^workflow run/).map { |c| c[/pr=(\d+)/, 1] }
def commented(calls) = calls.grep(/^pr comment/).map { |c| c[/comment (\d+)/, 1] }

puts "\ndispatch-bump-ci"

check("a bump PR with no CI run on its head (left by a cancelled run) is dispatched and commented") do
  ok, calls = dispatch(["7 bump-blackmagic-x-1.2 aaa"])
  ok && dispatched(calls) == ["7"] && commented(calls) == ["7"]
end

check("a run already on the PR head prevents a duplicate dispatch and comment") do
  ok, calls = dispatch(["7 bump-blackmagic-x-1.2 aaa"], runs: ["aaa"], commented: ["7"])
  ok && dispatched(calls).empty? && commented(calls).empty?
end

check("a missing comment is retried on the next run without redispatching CI") do
  ok, calls = dispatch(["7 bump-blackmagic-x-1.2 aaa"], runs: ["aaa"])
  ok && dispatched(calls).empty? && commented(calls) == ["7"]
end

check("non-bump PRs are ignored") do
  ok, calls = dispatch(["8 feature aaa"])
  ok && dispatched(calls).empty?
end

check("a failed dispatch fails the step, skips the comment, and still dispatches the other PRs") do
  ok, calls = dispatch(["7 bump-a-1 aaa", "9 bump-b-1 bbb"], failing: ["7"])
  !ok && dispatched(calls) == ["7", "9"] && commented(calls) == ["9"]
end

check("the failed dispatch is retried on the next run, without recreating the PR") do
  ok, calls = dispatch(["7 bump-a-1 aaa", "9 bump-b-1 bbb"], runs: ["bbb"], commented: ["9"])
  ok && dispatched(calls) == ["7"] && commented(calls) == ["7"]
end

check("a failed comment fails the step but still processes the other PRs") do
  ok, calls = dispatch(["7 bump-a-1 aaa", "9 bump-b-1 bbb"], failing_comments: ["7"])
  !ok && dispatched(calls) == ["7", "9"] && commented(calls) == ["7", "9"]
end

check("a failed PR snapshot fails the step and dispatches nothing") do
  ok, calls = dispatch([], pr_list_fails: true)
  !ok && dispatched(calls).empty?
end

check("no open PRs is a successful no-op") do
  ok, calls = dispatch([])
  ok && dispatched(calls).empty?
end

report_failures!
