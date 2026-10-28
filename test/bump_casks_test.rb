# typed: false
# frozen_string_literal: true

# Tests for `bin/bump-casks` (bump.yml) and `bin/report-run` (bump.yml, audit-online.yml), against stub
# `brew` and `gh` on PATH that answer from a fixtures directory and log every call.
#
# Run with `brew ruby test/bump_casks_test.rb`.

require "open3"
require "tmpdir"
require_relative "support"

BUMP_SCRIPT = File.expand_path("../bin/bump-casks", __dir__).freeze
REPORT_SCRIPT = File.expand_path("../bin/report-run", __dir__).freeze

BUMP_STUB_BREW = <<~SH
  #!/bin/bash
  echo "brew $*" >> "$FIXTURES/log"
  case "$1" in
    --repo) echo "$FIXTURES/tap" ;;
    bump)
      cask=${*: -1}; cask=${cask##*/}
      cat "$FIXTURES/bump-$cask.out" 2>/dev/null
      [[ ! -e "$FIXTURES/bump-$cask.fails" ]] ;;
  esac
SH

BUMP_STUB_GH = <<~SH
  #!/bin/bash
  echo "gh $*" >> "$FIXTURES/log"
  case "$1 $2" in
    "issue list") cat "$FIXTURES/issues.json" 2>/dev/null || echo '[]' ;;
  esac
SH

REGISTRATION_OUT = <<~OUT
  \e[34m==>\e[0m \e[1mblackmagic-davinci-resolve\e[0m
  Current cask version:     21.1
  Latest livecheck version: 21.1.1
  ::error::This download requires registration with Blackmagic Design, and 8 of the
OUT

def with_stubs(casks: [], outputs: {}, failing: [], issues: nil)
  Dir.mktmpdir do |dir|
    { "brew" => BUMP_STUB_BREW, "gh" => BUMP_STUB_GH }.each do |name, body|
      File.write("#{dir}/#{name}", body)
      File.chmod(0755, "#{dir}/#{name}")
    end
    FileUtils.mkdir_p("#{dir}/tap/Casks")
    casks.each { |cask| File.write("#{dir}/tap/Casks/#{cask}.rb", "") }
    outputs.each { |cask, out| File.write("#{dir}/bump-#{cask}.out", out) }
    failing.each { |cask| File.write("#{dir}/bump-#{cask}.fails", "") }
    File.write("#{dir}/issues.json", issues) if issues
    env = { "PATH" => "#{dir}:#{ENV.fetch("PATH")}", "FIXTURES" => dir, "TAP" => "o/t", "REPO" => "o/r" }
    yield env, -> { File.exist?("#{dir}/log") ? File.readlines("#{dir}/log", chomp: true) : [] }
  end
end

def bump(report_only: false, **stubs)
  with_stubs(**stubs) do |env, calls|
    _, status = Open3.capture2e(env.merge("REPORT_ONLY" => report_only.to_s), BUMP_SCRIPT)
    [status.success?, calls.call]
  end
end

def report(status, issues: "[]")
  with_stubs(issues:) do |env, calls|
    env = env.merge("WORKFLOW" => "Bump casks", "RUN_URL" => "https://run/1")
    _, result = Open3.capture2e(env, REPORT_SCRIPT, status)
    [result.success?, calls.call.grep(/^gh issue (create|comment|close)/)]
  end
end

puts "\nbump-casks"

check("each cask is bumped on its own, opening PRs") do
  ok, calls = bump(casks: %w[blackmagic-a blackmagic-b])
  ok && calls.grep(/^brew bump/) == ["brew bump --cask --open-pr --no-fork o/t/blackmagic-a",
                                     "brew bump --cask --open-pr --no-fork o/t/blackmagic-b"]
end

check("report-only opens no PRs") do
  ok, calls = bump(casks: %w[blackmagic-a], report_only: true)
  ok && calls.grep(/^brew bump/) == ["brew bump --cask o/t/blackmagic-a"]
end

check("a cask needing registration files a manual-bump issue and does not fail the run") do
  ok, calls = bump(casks: %w[blackmagic-davinci-resolve blackmagic-z], failing: %w[blackmagic-davinci-resolve],
                   outputs: { "blackmagic-davinci-resolve" => REGISTRATION_OUT })
  ok && calls.any? do |c|
    c.include?("issue create") && c.include?("Manual bump: blackmagic-davinci-resolve 21.1.1")
  end &&
    calls.any? { |c| c.include?("bump --cask --open-pr --no-fork o/t/blackmagic-z") }
end

check("an existing manual-bump issue, even closed, is not filed again") do
  ok, calls = bump(casks: %w[blackmagic-davinci-resolve], failing: %w[blackmagic-davinci-resolve],
                   outputs: { "blackmagic-davinci-resolve" => REGISTRATION_OUT },
                   issues: '[{"title":"Manual bump: blackmagic-davinci-resolve 21.1.1"}]')
  ok && calls.none? { |c| c.include?("issue create") }
end

check("report-only files no issues") do
  ok, calls = bump(casks: %w[blackmagic-davinci-resolve], failing: %w[blackmagic-davinci-resolve],
                   outputs: { "blackmagic-davinci-resolve" => REGISTRATION_OUT }, report_only: true)
  ok && calls.none? { |c| c.include?("issue create") }
end

check("any other bump failure fails the run after bumping the rest") do
  ok, calls = bump(casks: %w[blackmagic-a blackmagic-b], failing: %w[blackmagic-a])
  !ok && calls.any? { |c| c.end_with?("o/t/blackmagic-b") }
end

puts "\nreport-run"

OPEN_ISSUE = '[{"number":5,"title":"Scheduled run failing: Bump casks"}]'

check("a failure with no open issue opens one for triage") do
  ok, calls = report("failure")
  ok && calls.size == 1 && calls.first.include?("issue create") && calls.first.include?("--label needs-triage")
end

check("a repeated failure comments on the open issue") do
  ok, calls = report("failure", issues: OPEN_ISSUE)
  ok && calls.size == 1 && calls.first.start_with?("gh issue comment 5")
end

check("a success closes the open issue") do
  ok, calls = report("success", issues: OPEN_ISSUE)
  ok && calls.size == 1 && calls.first.start_with?("gh issue close 5")
end

check("a success with no open issue does nothing") do
  ok, calls = report("success")
  ok && calls.empty?
end

check("an issue with a different title is not reused") do
  ok, calls = report("failure", issues: '[{"number":6,"title":"Scheduled run failing: Bump casks again"}]')
  ok && calls.first.include?("issue create")
end

report_failures!
