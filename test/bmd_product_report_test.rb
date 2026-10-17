# typed: false
# frozen_string_literal: true

# Tests for `BmdProductReport`: grouping catalog releases into products, diffing that against
# casks-that-exist plus the skip-list, and the `gh` failure paths (#29) against stubbed responses.
# The catalog read and live `gh` calls are not exercised here.
#
# Run with `brew ruby test/bmd_product_report_test.rb`.

require "stringio"
require_relative "../lib/bmd_product_report"
require_relative "support"

def sample_release(name, date: "01 Jan 2026", numeric_date: 1, registration: false, terms: false, families: [])
  {
    "name" => name, "date" => date, "numericDate" => numeric_date,
    "requiresRegistration" => registration, "requiresTermsAndConditions" => terms,
    "relatedFamilies" => families, "urls" => { BmdCatalog::PLATFORM => [{ "downloadId" => "x" }] }
  }
end

puts "\nproducts"

PRODUCT_CATALOG = [
  sample_release("Blackmagic Camera 10.2"),
  sample_release("Blackmagic Camera 10.2.2 Update", numeric_date: 2),
  sample_release("Blackmagic Camera 10.2 SDK"),
  sample_release("Blackmagic Camera 9.8 Public Beta"),
  sample_release("Blackmagic Ethernet Switch 1.2"),
  sample_release("Blackmagic RAW SDK 3.5"),
].freeze

check("groups releases by base name, stripping version and Update") do
  BmdProductReport.products(PRODUCT_CATALOG).keys.sort ==
    ["Blackmagic Camera", "Blackmagic Ethernet Switch", "Blackmagic RAW SDK"]
end

check("drops releases matching the SDK regex before grouping") do
  BmdProductReport.products(PRODUCT_CATALOG)["Blackmagic Camera"][:count] == 2
end

check("drops releases matching the beta regex before grouping") do
  BmdProductReport.products(PRODUCT_CATALOG)["Blackmagic Camera"][:latest]["name"].exclude?("Beta")
end

check("a product whose own name contains SDK still groups (only the release-name pattern is a skip)") do
  BmdProductReport.products(PRODUCT_CATALOG).key?("Blackmagic RAW SDK")
end

check("picks the latest release by numericDate as the group's representative") do
  BmdProductReport.products(PRODUCT_CATALOG)["Blackmagic Camera"][:latest]["name"] ==
    "Blackmagic Camera 10.2.2 Update"
end

puts "\nmissing"

check("products with casks are not reported as missing") do
  releases = [
    sample_release("Blackmagic Ethernet Switch 1.2"),
    sample_release("Blackmagic Camera 10.2.2 Update"),
  ]
  BmdProductReport.missing(releases, Set["Blackmagic Ethernet Switch", "Blackmagic Camera"]).empty?
end

check("products that should never get casks are hidden by the skip-list") do
  BmdProductReport.missing([sample_release("Blackmagic RAW SDK 3.5")], Set.new).empty?
end

check("backlog products are reported until they get casks") do
  BmdProductReport.missing([sample_release("Blackmagic Video Assist 4.2")], Set.new)
                  .key?("Blackmagic Video Assist")
end

check("products with casks are not hidden by the skip-list") do
  [
    "Blackmagic Audio Monitor", "Blackmagic Camera", "Blackmagic Camera ProDock", "Blackmagic Cintel",
    "Blackmagic Converters", "Blackmagic Duplicator", "Blackmagic MultiView", "Blackmagic RAW Player",
    "Blackmagic RAW Speed Test", "Blackmagic Streaming", "Blackmagic Videohub"
  ].none? { |name| BmdSkipList::SKIP_PRODUCTS.key?(name) }
end

check("a product in neither Casks/ nor the skip-list is reported with the fields a human needs") do
  info = BmdProductReport.missing(
    [sample_release("Some New Thing 1.0", registration: true, terms: true, families: ["cameras"])], Set.new
  )["Some New Thing"]
  info[:count] == 1 && info[:latest]["requiresRegistration"] && info[:latest]["requiresTermsAndConditions"] &&
    info[:latest]["relatedFamilies"] == ["cameras"]
end

puts "\nreport (stubbed gh)"

FakeStatus = Struct.new(:exitstatus) do
  def success? = exitstatus.zero?
end

# Replaces `Open3.capture3` with canned `gh` responses keyed by subcommand; returns every call made.
def with_gh(responses)
  calls = []
  original = Open3.method(:capture3)
  Open3.define_singleton_method(:capture3) do |*cmd, **_opts|
    calls << cmd
    out, code = responses.fetch(cmd[2])
    [out, "boom", FakeStatus.new(code)]
  end
  yield calls
ensure
  Open3.define_singleton_method(:capture3, original)
end

def creates(calls) = calls.count { |cmd| cmd[2] == "create" }

MISSING = BmdProductReport.missing([sample_release("Some New Thing 1.0")], Set.new).freeze

def quietly
  out = $stdout
  $stdout = StringIO.new
  yield
ensure
  $stdout = out
end

check_raises("failed issue list raises instead of reading as empty", BmdProductReport::ReportError, "boom") do
  with_gh("list" => ["", 1], "create" => ["", 0]) { BmdProductReport.send(:report, MISSING) }
end

check("failed issue list never calls create") do
  with_gh("list" => ["", 1], "create" => ["", 0]) do |calls|
    BmdProductReport.send(:report, MISSING)
  rescue BmdProductReport::ReportError
    creates(calls).zero?
  end
end

check_raises("invalid JSON from issue list raises", BmdProductReport::ReportError, "invalid JSON") do
  with_gh("list" => ["not json", 0]) { BmdProductReport.send(:report, MISSING) }
end

check_raises("failed create raises", BmdProductReport::ReportError, "boom") do
  with_gh("list" => ["[]", 0], "create" => ["", 1]) { quietly { BmdProductReport.send(:report, MISSING) } }
end

check("a successful empty list is valid and files one issue") do
  with_gh("list" => ["[]", 0], "create" => ["https://example/1\n", 0]) do |calls|
    quietly { BmdProductReport.send(:report, MISSING) }
    creates(calls) == 1
  end
end

check("an open issue reporting the same set is not re-filed") do
  existing = [{ "number" => 7, "title" => BmdProductReport::ISSUE_TITLE,
                "body" => BmdProductReport.render_issue_body(MISSING) }].to_json
  with_gh("list" => [existing, 0], "create" => ["", 0]) do |calls|
    2.times { quietly { BmdProductReport.send(:report, MISSING) } }
    creates(calls).zero?
  end
end

report_failures!
