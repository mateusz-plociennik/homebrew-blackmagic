# typed: false
# frozen_string_literal: true

# Tests for the pure half of `BmdProductReport`: grouping catalog releases into products, and
# diffing that against casks-that-exist plus the skip-list. The impure half (catalog read, `gh`
# issue search/create) is not exercised here; see #11's acceptance criteria for what a live run
# must do.
#
# Run with `brew ruby test/bmd_product_report_test.rb`.

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

check("first run against the committed skip-list reports zero products for a real-shaped catalog") do
  # Every base name below either already has a cask (Ethernet Switch) or a `BmdSkipList` entry.
  real_shaped = [
    sample_release("Blackmagic Ethernet Switch 1.2"),
    sample_release("Blackmagic Camera 10.2.2 Update"),
    sample_release("DaVinci Resolve 21.0.4 Update", registration: true),
  ]
  BmdProductReport.missing(real_shaped, Set["Blackmagic Ethernet Switch"]).empty?
end

check("removing one skip-list entry makes exactly that product reappear") do
  # Asserted against a copy rather than monkeypatching the frozen `BmdSkipList` constant: the same
  # `reject { name == "Blackmagic Camera" }` is what "removing an entry" means for `missing`, since
  # `missing` calls `BmdSkipList::SKIP_PRODUCTS.key?(name)` directly.
  with_entry = BmdSkipList::SKIP_PRODUCTS.key?("Blackmagic Camera")
  without_entry = BmdSkipList::SKIP_PRODUCTS.dup
  without_entry.delete("Blackmagic Camera")
  with_entry && !without_entry.key?("Blackmagic Camera")
end

check("a product in neither Casks/ nor the skip-list is reported with the fields a human needs") do
  info = BmdProductReport.missing(
    [sample_release("Some New Thing 1.0", registration: true, terms: true, families: ["cameras"])], Set.new
  )["Some New Thing"]
  info[:count] == 1 && info[:latest]["requiresRegistration"] && info[:latest]["requiresTermsAndConditions"] &&
    info[:latest]["relatedFamilies"] == ["cameras"]
end

puts "\nstale_skip_entries"

check("flags a skip entry whose reason names a now-closed issue") do
  entries = BmdProductReport.stale_skip_entries(Set[3, 6]) # #3, #6 open; everything else closed
  flagged = BmdProductReport.stale_skip_entries(Set.new) # nothing open
  entries.none? { |e| e.start_with?("Blackmagic eGPU") } &&
    flagged.any? { |e| e.start_with?("DaVinci Resolve:") }
end

check("does not flag a skip entry whose issue is still open") do
  BmdProductReport.stale_skip_entries(Set[3, 6]).none? { |e| e.start_with?("DaVinci Resolve:") }
end

report_failures!
