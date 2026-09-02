# typed: false
# frozen_string_literal: true

# Tests for the pure half of `BmdCatalog`: how a cask's product name and version turn into the one
# catalog release they mean. The impure half (`releases`, which curls 1.5 MB from Blackmagic) is not
# exercised here — every test below feeds `find_mac_release` a literal array.
#
# Run with `brew ruby test/bmd_catalog_test.rb`. Plain assertions rather than a framework: Homebrew's
# portable Ruby ships no minitest, and `brew ruby` is the only interpreter that can load
# `utils/curl` — so a gem-based runner would mean vendoring a test stack to test two methods.
#
# Homebrew's own rspec suite (`brew tests`) covers only `Library/Homebrew`; taps get `brew test-bot
# --only-tap-syntax`, which is style and audit, not behaviour. Hence this file.

require_relative "../lib/bmd_catalog"
require_relative "support"

def release(name, download_id: "id-for-#{name}", platform: BmdCatalog::PLATFORM)
  { "name" => name, "urls" => { platform => [{ "downloadId" => download_id }] } }
end

puts "\nrelease_regex"

ETHERNET = BmdCatalog.release_regex("Blackmagic Ethernet Switch").freeze
CAMERA = BmdCatalog.release_regex("Blackmagic Camera").freeze
RESOLVE = BmdCatalog.release_regex("DaVinci Resolve").freeze

# The suffixless shape, which is all `blackmagic-ethernet-switch` has ever seen.
check("matches a bare `<product> <version>` name") { "Blackmagic Ethernet Switch 1.2" =~ ETHERNET }
check("captures the version from a bare name") { "Blackmagic Ethernet Switch 1.2"[ETHERNET, 1] == "1.2" }

# The regression this whole change exists for: point releases carry ` Update`, and a regex that
# missed them left a cask pinned at its last suffixless release with nothing reporting a problem.
check("matches an ` Update` release") { "Blackmagic Camera 10.2.2 Update" =~ CAMERA }
check("captures the version from an ` Update` release") do
  "Blackmagic Camera 10.2.2 Update"[CAMERA, 1] == "10.2.2"
end

# Versions run from one to four segments in the catalog: `DaVinci Resolve Project Server 21`,
# `HyperDeck 9.0.2`, `Blackmagic Camera 9.9.1`.
check("matches a single-segment version") { "Blackmagic Camera 21" =~ CAMERA }
check("matches a four-segment version") { "Blackmagic Camera 1.2.3.4" =~ CAMERA }

# Anchoring is the point, and both ends carry weight. `DaVinci Resolve Studio` is a *different
# product* from `DaVinci Resolve`, sold separately; ` SDK` builds are developer libraries, not apps;
# betas are a channel this tap does not ship. A prefix match would swallow all three, and pre-16
# Studio releases were named `DaVinci Resolve 15.3 Studio`, so the trailing junk is not always a
# recognisable word.
check("rejects ` SDK`") { "Blackmagic Camera 10.2 SDK" !~ CAMERA }
check("rejects ` Beta`") { "Blackmagic Camera 10.2 Beta" !~ CAMERA }
check("rejects ` Public Beta`") { "Blackmagic Camera 10.2 Public Beta" !~ CAMERA }
check("rejects a trailing-word product variant") { "DaVinci Resolve 15.3 Studio" !~ RESOLVE }
check("rejects a leading-word product variant") { "DaVinci Resolve Studio 21.0.4 Update" !~ RESOLVE }
check("rejects a longer product with the same prefix") { "Blackmagic Camera ProDock 1.1.1" !~ CAMERA }
check("rejects a name with no version") do
  "Blackmagic RAW Player" !~ BmdCatalog.release_regex("Blackmagic RAW Player")
end

# `Blackmagic RAW` is a prefix of `Blackmagic RAW Player`, `Blackmagic RAW Speed Test` and
# `Blackmagic RAW SDK`, so its regex is the one most likely to over-match.
check("rejects siblings of a prefix-shaped product") do
  raw = BmdCatalog.release_regex("Blackmagic RAW")
  ["Blackmagic RAW Player 1.4", "Blackmagic RAW Speed Test 1.4", "Blackmagic RAW SDK 3.0"]
    .none? { |name| name =~ raw }
end

# A product name is interpolated into a regex, so any regex metacharacter in it has to be inert.
check("escapes regex metacharacters in the product name") do
  "Foo+Bar 1.0" =~ BmdCatalog.release_regex("Foo+Bar") && "FooXBar 1.0" !~ BmdCatalog.release_regex("Foo+Bar")
end

puts "\nfind_mac_release"

CATALOG = [
  release("Blackmagic Camera 10.2"),
  release("Blackmagic Camera 10.2.2 Update"),
  release("Blackmagic Camera 10.2.2 SDK"),
  release("Blackmagic Camera ProDock 1.1.1"),
  release("Blackmagic Ethernet Switch 1.2"),
].freeze

check("finds a suffixless release by version") do
  BmdCatalog.find_mac_release(CATALOG, "Blackmagic Camera", "10.2")["name"] == "Blackmagic Camera 10.2"
end

# The version alone cannot tell you whether upstream named a release `10.2.2` or `10.2.2 Update`, and
# a cask only holds the version — so the lookup has to accept either. This is what lets `version`
# stay the single thing `brew bump-cask-pr` has to rewrite.
check("finds an ` Update` release by the same version a cask pins") do
  BmdCatalog.find_mac_release(CATALOG, "Blackmagic Camera", "10.2.2")["name"] == "Blackmagic Camera 10.2.2 Update"
end

check("does not confuse a longer product name for its prefix") do
  found = BmdCatalog.find_mac_release(CATALOG, "Blackmagic Camera ProDock", "1.1.1")
  found["name"] == "Blackmagic Camera ProDock 1.1.1"
end

# A version is matched whole, not as a prefix: a cask pinned at `10` must not settle for `10.2`.
check_raises("does not treat a version as a prefix of a longer one", BmdCatalog::CatalogError,
             'no release "Blackmagic Camera 10"') do
  BmdCatalog.find_mac_release(CATALOG, "Blackmagic Camera", "10")
end

check_raises("names the product and version when nothing matches", BmdCatalog::CatalogError,
             "Blackmagic Camera 9.9") do
  BmdCatalog.find_mac_release(CATALOG, "Blackmagic Camera", "9.9")
end

# No (product, version) pair in the catalog carries both a bare and an ` Update` name today — all
# 977 pairs were checked. Should upstream ever ship both, guessing which one a cask meant would pin
# a checksum against an artifact chosen by luck, so refuse instead and say what was found.
check_raises("refuses to guess between two matches", BmdCatalog::CatalogError, "matches 2 releases") do
  both = [release("HyperDeck 9.0.2"), release("HyperDeck 9.0.2 Update")]
  BmdCatalog.find_mac_release(both, "HyperDeck", "9.0.2")
end

check_raises("reports a release that has no macOS build", BmdCatalog::CatalogError, "no Mac OS X build") do
  windows_only = [release("HyperDeck 9.0.2", platform: "Windows")]
  BmdCatalog.find_mac_release(windows_only, "HyperDeck", "9.0.2")
end

check_raises("reports a macOS build with no downloadId", BmdCatalog::CatalogError, "no Mac OS X build") do
  no_id = [release("HyperDeck 9.0.2", download_id: nil)]
  BmdCatalog.find_mac_release(no_id, "HyperDeck", "9.0.2")
end

check("returns the macOS downloadId") do
  BmdCatalog.mac_download_id_from(CATALOG, "Blackmagic Camera", "10.2.2") == "id-for-Blackmagic Camera 10.2.2 Update"
end

puts "\nMAC_RELEASES (livecheck strategy)"

# What `livecheck` actually runs: the proc receives the parsed catalog and the cask's regex, and
# returns every version whose release matches. `brew bump` takes the newest of these.
check("collects both bare and ` Update` versions, and nothing else") do
  json = { "downloads" => CATALOG }
  versions = BmdCatalog::MAC_RELEASES.call(json, CAMERA).compact
  versions.sort == ["10.2", "10.2.2"]
end

check("ignores releases with no macOS build") do
  json = { "downloads" => [release("Blackmagic Camera 10.3", platform: "Windows")] }
  BmdCatalog::MAC_RELEASES.call(json, CAMERA).compact.empty?
end

report_failures!
