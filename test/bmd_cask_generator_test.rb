# typed: false
# frozen_string_literal: true

# Tests for the pure half of `BmdCaskGenerator`: readme -> `desc` draft, family -> homepage, token
# derivation, and the small string-templating helpers a generated cask needs. The impure half
# (catalog read, readme fetch, artifact download and introspection) is not exercised here — see #10's
# acceptance criteria for the regression that reproduces `blackmagic-ethernet-switch` end to end.
#
# Run with `brew ruby test/bmd_cask_generator_test.rb`. Same plain-assertion style as
# `bmd_catalog_test.rb`; see that file for why.

require_relative "../lib/bmd_cask_generator"
require_relative "support"

puts "\ntoken_for"

check("prefixes blackmagic- to a product with the brand already in its name") do
  BmdCaskGenerator.token_for("Blackmagic Ethernet Switch") == "blackmagic-ethernet-switch"
end

check("prefixes blackmagic- to a product without the brand in its name") do
  BmdCaskGenerator.token_for("HyperDeck") == "blackmagic-hyperdeck"
end

check("hyphenates spaces") { BmdCaskGenerator.token_for("ATEM Switchers") == "blackmagic-atem-switchers" }

check("does not double the prefix") do
  BmdCaskGenerator.token_for("Blackmagic Camera") == "blackmagic-camera"
end

puts "\ndesc_draft_from_readme"

ETHERNET_README = <<~HTML
  <article class="readMe">
    <h2>About Blackmagic Ethernet Switch</h2>
    <h3>Welcome to the Blackmagic Ethernet Switch Software!</h3>
    <p>
      This software includes everything you need to set up your Blackmagic
      Ethernet Switch with your Macintosh computer.
    </p>
    <h3>Minimum system requirements for Mac OS</h3>
    <ul><li>macOS 15.0 Sequoia.</li></ul>
  </article>
HTML

check("drafts the welcome paragraph, tags and whitespace stripped") do
  BmdCaskGenerator.desc_draft_from_readme(ETHERNET_README) ==
    "This software includes everything you need to set up your Blackmagic Ethernet Switch with " \
    "your Macintosh computer."
end

check("returns nil when there is no welcome paragraph to draft from") do
  BmdCaskGenerator.desc_draft_from_readme("<article><h2>About Foo</h2></article>").nil?
end

puts "\nhomepage_for_family"

check("builds the family homepage") do
  BmdCaskGenerator.homepage_for_family("routing-and-distribution") ==
    "https://www.blackmagicdesign.com/support/family/routing-and-distribution"
end

check("returns nil for a blank family") { BmdCaskGenerator.homepage_for_family(nil).nil? }

puts "\nmacos_symbol_for"

check("rounds a version below the oldest expressible symbol up to :big_sur") do
  BmdCaskGenerator.macos_symbol_for("10.14") == :big_sur
end

check("matches an exact symbol version") { BmdCaskGenerator.macos_symbol_for("11") == :big_sur }

check("rounds a version between two symbols up to the higher one") do
  BmdCaskGenerator.macos_symbol_for("14.5") == :sequoia
end

check("returns nil when the pkg enforces nothing") { BmdCaskGenerator.macos_symbol_for(nil).nil? }

puts "\nparse_distribution"

# The installer's own OS check, both ways round — Resolve writes the comparison with the literal
# first, and reading only the other order scaffolded a cask with no `depends_on macos:` at all.
DISTRIBUTION_TEMPLATE = <<~XML
  <pkg-ref id="com.blackmagic-design.ManifestLite" installKBytes="1"/>
  <script>
  pm_install_check() {
    if (%<comparison>s > 0) { my.result.type = 'Fatal'; return false; }
    return true;
  }
  </script>
XML

check("reads a minimum OS from a literal-first comparison") do
  xml = format(DISTRIBUTION_TEMPLATE, comparison: "system.compareVersions('15.0', system.version.ProductVersion)")
  BmdCaskGenerator.parse_distribution(xml) == [["com.blackmagic-design.ManifestLite"], "15.0"]
end

check("reads a minimum OS from a ProductVersion-first comparison") do
  xml = format(DISTRIBUTION_TEMPLATE, comparison: 'system.compareVersions(system.version.ProductVersion, "10.15")')
  BmdCaskGenerator.parse_distribution(xml).last == "10.15"
end

check("returns no minimum OS when the installer checks nothing") do
  xml = format(DISTRIBUTION_TEMPLATE, comparison: "0")
  BmdCaskGenerator.parse_distribution(xml).last.nil?
end

puts "\nlatest_mac_release"

check("skips a newer release without a macOS downloadId") do
  releases = [
    {
      "name" => "Blackmagic Ethernet Switch 1.2",
      "urls" => { BmdCatalog::PLATFORM => [{ "downloadId" => "usable" }] },
    },
    { "name" => "Blackmagic Ethernet Switch 1.3", "urls" => { BmdCatalog::PLATFORM => [{}] } },
  ]
  BmdCaskGenerator.latest_mac_release(releases, "Blackmagic Ethernet Switch")["name"] ==
    "Blackmagic Ethernet Switch 1.2"
end

puts "\npkgutil_regex_for"

check("finds the common prefix across three receipts") do
  BmdCaskGenerator.pkgutil_regex_for(
    ["com.blackmagic-design.EthernetSwitch", "com.blackmagic-design.EthernetSwitchAssets",
     "com.blackmagic-design.EthernetSwitchUninstaller"],
  ) == "com.blackmagic-design.EthernetSwitch.*"
end

check("returns a single identifier verbatim, with no wildcard") do
  BmdCaskGenerator.pkgutil_regex_for(["com.blackmagic-design.Foo"]) == "com.blackmagic-design.Foo"
end

check("uses exact alternatives when receipts share only a namespace") do
  BmdCaskGenerator.pkgutil_regex_for(
    ["com.blackmagic-design.CloudStore", "com.blackmagic-design.CloudStoreHelper"],
  ) == "com.blackmagic-design.CloudStore.*"
end

check("does not emit a namespace-wide uninstall regex") do
  BmdCaskGenerator.pkgutil_regex_for(
    ["com.blackmagic-design.CloudStore", "com.blackmagic-design.VideoAssist"],
  ) == "(?:com\\.blackmagic\\-design\\.CloudStore|com\\.blackmagic\\-design\\.VideoAssist)"
end

check("uses exact alternatives for a short product prefix") do
  BmdCaskGenerator.pkgutil_regex_for(
    ["com.blackmagic-design.Switcher", "com.blackmagic-design.Server"],
  ) == "(?:com\\.blackmagic\\-design\\.Switcher|com\\.blackmagic\\-design\\.Server)"
end

puts "\nversioned_template"

check("interpolates the exact version in a url") do
  BmdCaskGenerator.versioned_template(
    "https://sw.blackmagicdesign.com/EthernetSwitch/v1.2/Blackmagic_Ethernet_Switch_Macintosh_1.2.zip", "1.2"
  ) == "https://sw.blackmagicdesign.com/EthernetSwitch/v\#{version}/Blackmagic_Ethernet_Switch_Macintosh_\#{version}.zip"
end

check("interpolates the exact version in a pkg filename") do
  BmdCaskGenerator.versioned_template("Install Ethernet Switch 1.2.pkg", "1.2") ==
    "Install Ethernet Switch \#{version}.pkg"
end

check("does not swallow a longer version that merely starts with the same digits") do
  BmdCaskGenerator.versioned_template("Foo 1.2.3.zip", "1.2").nil?
rescue BmdCaskGenerator::GeneratorError
  true
end

puts "\nname_stanzas"

check("drops installer/uninstaller helper apps") do
  BmdCaskGenerator.name_stanzas(
    "Blackmagic Ethernet Switch", ["Ethernet Switch Setup", "Uninstall Ethernet Switch"]
  ) == ["Blackmagic Ethernet Switch"]
end

check("keeps a real app name alongside the catalog product name") do
  BmdCaskGenerator.name_stanzas("Blackmagic Camera", ["Blackmagic Camera"]) == ["Blackmagic Camera"]
end

report_failures!
