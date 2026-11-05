# typed: false
# frozen_string_literal: true

require "open3"
require "tmpdir"
require_relative "support"

SCRIPT = File.expand_path("../bin/compare-receipts", __dir__).freeze

def compare(before, after, retained = :none)
  Dir.mktmpdir do |dir|
    files = { before:, after: }
    files[:retained] = retained if retained != :none
    paths = files.map do |name, receipts|
      path = File.join(dir, name.to_s)
      File.write(path, receipts.join("\n")) if receipts
      path
    end
    out, err, status = Open3.capture3(SCRIPT, *paths)
    [out + err, status.exitstatus]
  end
end

puts "compare-receipts"

check("unchanged receipts pass") do
  compare(%w[com.a com.b], %w[com.b com.a]) == ["", 0]
end

check("a leftover new receipt fails and is named") do
  out, code = compare(%w[com.a], %w[com.a com.new])
  code == 1 && out.include?("left receipts behind: com.new")
end

check("a removed pre-existing receipt fails and is named") do
  out, code = compare(%w[com.neighbor], [])
  code == 1 && out.include?("removed pre-existing receipts: com.neighbor")
end

check("an unreadable snapshot is an error, not an empty list") do
  out, code = compare(nil, [])
  code == 2 && out.include?("cannot read receipt snapshot")
end

check("a retained receipt left behind passes; comments and blank lines are ignored") do
  compare(%w[com.a], %w[com.a com.kept], ["# shared with Camera", "", "com.kept  # driver"]) == ["", 0]
end

check("a retained receipt the uninstall removed fails and is named") do
  out, code = compare(%w[com.a], %w[com.a], %w[com.kept])
  code == 1 && out.include?("did not keep retained receipts: com.kept")
end

check("retaining one receipt still fails on another leftover") do
  out, code = compare([], %w[com.kept com.new], %w[com.kept])
  code == 1 && out.include?("left receipts behind: com.new") && out.exclude?("com.kept")
end

check("an unreadable retained list is an error") do
  out, code = compare([], [], nil)
  code == 2 && out.include?("cannot read receipt snapshot")
end

report_failures!
