# typed: false
# frozen_string_literal: true

require "open3"
require "tmpdir"
require_relative "support"

SCRIPT = File.expand_path("../bin/compare-receipts", __dir__).freeze

def compare(before, after)
  Dir.mktmpdir do |dir|
    paths = { before:, after: }.map do |name, receipts|
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

report_failures!
