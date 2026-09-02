# typed: false
# frozen_string_literal: true

# Shared harness for this tap's `brew ruby test/*_test.rb` scripts: plain assertions, no framework —
# Homebrew's portable Ruby ships no minitest, and `brew ruby` is the only interpreter that can load
# `utils/curl`, so a gem-based runner would mean vendoring a test stack to test a handful of methods.
# Homebrew's own rspec suite (`brew tests`) covers only `Library/Homebrew`; taps get `brew test-bot
# --only-tap-syntax`, which is style and audit, not behaviour. Hence these files.
#
# Every test file requires this rather than redefining `Failures`, `check` and `FAILURES` itself:
# `brew test-bot --only-tap-syntax` runs RuboCop over the whole tap at once, and duplicate top-level
# definitions across files trip its `Lint/DuplicateMethods` and `Lint/ConstantReassignment` cops.

# Holds what failed. A wrapper object rather than a bare `FAILURES = []`, because Homebrew's style
# rules require a constant to be frozen, and a frozen array cannot be appended to. Freezing the
# wrapper leaves `list` mutable.
class Failures
  attr_reader :list

  def initialize
    @list = []
  end
end

FAILURES = Failures.new.freeze

def check(description)
  result = yield
  raise "expected a truthy result, got #{result.inspect}" unless result

  puts "  ok  #{description}"
rescue => e
  FAILURES.list << "#{description}\n        #{e.message.lines.first.to_s.strip}"
  puts "FAIL  #{description}"
end

# Asserts that `block` raises `error_class` and that its message mentions `expected` — these
# messages are the whole diagnostic when a lookup fails mid-install or mid-generate.
def check_raises(description, error_class, expected)
  begin
    yield
  rescue error_class => e
    return check(description) { e.message.include?(expected) }
  end

  check(description) { raise "no #{error_class} raised" }
end

def report_failures!
  puts
  if FAILURES.list.empty?
    puts "All checks passed."
  else
    puts "#{FAILURES.list.size} failed:"
    FAILURES.list.each { |failure| puts "  - #{failure}" }
    exit 1
  end
end
