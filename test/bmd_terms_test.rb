# typed: false
# frozen_string_literal: true

# Tests for terms-and-conditions handling in `BmdDownloadStrategy` and `BmdCatalog`.
#
# Run with `brew ruby test/bmd_terms_test.rb`. Plain assertions rather than a framework.
#
# Terms acceptance is checked in the download strategy (so it only runs at install time, not
# livecheck), and the behavior requires both a catalog entry with `requiresTermsAndConditions`
# and the user's explicit opt-in in the config file.

require "tmpdir"
require "json"

require_relative "../lib/bmd_catalog"
require_relative "../lib/bmd_config"
require_relative "../lib/bmd_download_strategy"
require_relative "../lib/bmd_terms"
require_relative "support"

def with_terms_config(terms_accepted)
  config_data = { "agreeToTerms" => terms_accepted }
  Dir.mktmpdir("bmd-terms-test") do |dir|
    path = File.join(dir, "bmd-tap")
    Dir.mkdir(path)
    File.write(File.join(path, "config.json"), JSON.generate(config_data))

    # `XDG_CONFIG_HOME` is restored along with the field overrides: the tmpdir is gone after the block,
    # and leaving it pointing there would have every later check read a config path that cannot exist.
    cleared = BmdConfig::FIELDS.to_h { |name| [BmdConfig.env_var(name), nil] }
    overrides = cleared.merge("XDG_CONFIG_HOME" => dir)
    previous = overrides.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    overrides.each { |key, value| ENV[key] = value }

    yield
  ensure
    previous&.each { |key, value| ENV[key] = value }
  end
end

def release_with_terms(name, terms_slug, requires_terms: true, download_id: "test-id")
  {
    "name"                       => name,
    "requiresTermsAndConditions" => requires_terms,
    "termsAndConditions"         => terms_slug,
    "urls"                       => {
      BmdCatalog::PLATFORM => [{ "downloadId" => download_id }],
    },
  }
end

def release_without_terms(name, download_id: "test-id")
  {
    "name"                       => name,
    "requiresTermsAndConditions" => false,
    "urls"                       => {
      BmdCatalog::PLATFORM => [{ "downloadId" => download_id }],
    },
  }
end

puts "\nrequires_terms? flag detection"

check("detects requiresTermsAndConditions when true") do
  BmdCatalog.requires_terms?(release_with_terms("Test 1.0", "terms text"))
end

check("detects requiresTermsAndConditions as false") do
  !BmdCatalog.requires_terms?(release_with_terms("Test 1.0", "terms text", requires_terms: false))
end

check("treats missing requiresTermsAndConditions as false") do
  !BmdCatalog.requires_terms?(release_without_terms("Test 1.0"))
end

puts "\nacceptance in config"

check("rejects terms when config has no agreeToTerms key") do
  with_terms_config(nil) { !BmdConfig.accepts_terms? }
end

check("accepts terms when config has agreeToTerms: true") do
  with_terms_config(true) { BmdConfig.accepts_terms? }
end

check("rejects terms when config has agreeToTerms: false") do
  with_terms_config(false) { !BmdConfig.accepts_terms? }
end

puts "\ndownload_id_for with terms"

check("retrieves downloadId from a terms-gated release") do
  release = release_with_terms("Test 1.0", "bmd-standard-sdk", download_id: "special-id-123")
  BmdCatalog.download_id_for(release) == "special-id-123"
end

puts "\nreading the agreement out of Blackmagic's modal"

# Shaped like the real fragment: the agreement inside `<div class="tandc">`, registration-form chrome
# on either side of it, and a nested `<div>` inside the agreement.
MODAL_HTML = <<~HTML
  <div class="modal">
    <div class="tab-content">
      <label for="email">Email *</label><input name="email" />
    </div>
    <div class="tandc">
      <h1>Blackmagic Design Pty. Ltd.</h1>
      <p><b>IMPORTANT:</b> Read this before installing.</p>
      <div class="clause"><p>1 You may use the Software on a single system &amp; keep one copy.</p></div>
      <p>Contact: www.blackmagicdesign.com</p>
    </div>
    <div class="pop-footer"><a>Agree</a><a>Disagree</a></div>
  </div>
HTML

EXTRACTED = BmdTerms.extract(MODAL_HTML).freeze

check("extracts the agreement text") do
  EXTRACTED.include?("IMPORTANT: Read this before installing.")
end

check("keeps the agreement's nested elements, which hold numbered clauses") do
  EXTRACTED.include?("1 You may use the Software on a single system & keep one copy.")
end

check("stops at the end of the agreement, taking no form chrome with it") do
  EXTRACTED.exclude?("Email") && EXTRACTED.exclude?("Disagree")
end

check("keeps the agreement's line structure rather than running it together") do
  EXTRACTED.lines.length > 3
end

check_raises("refuses to invent text when the container is gone", BmdTerms::TermsError,
             "no longer contains") do
  BmdTerms.extract("<div class=\"modal\">Blackmagic redesigned the page</div>", "bmd-standard-sdk")
end

# An empty container read as "an agreement with no words in it" would have the refusal print nothing
# and still demand agreement to it, which is the one thing this path must not do.
check_raises("treats an empty container as unread, not as an empty agreement", BmdTerms::TermsError,
             "no longer contains") do
  BmdTerms.extract("<div class=\"tandc\">\n  <p>&nbsp;</p>\n</div>", "bmd-standard-sdk")
end

check("names the slug's own URL, which is where a person would read it") do
  BmdTerms.url("bmd-braw-sdk-2").end_with?("download-with-terms-start/bmd-braw-sdk-2")
end

puts "\nthe refusal itself"

# `refuse_terms!` is what the acceptance criteria are actually about, so it is exercised directly
# rather than asserted about: the checks above only prove the two inputs to the `_fetch` guard.
# `CurlDownloadStrategyError` subclasses `RuntimeError`, so raising it exits `brew install` non-zero.
#
# `text` is stubbed because it curls Blackmagic; `extract`, which is the part with logic in it, is
# tested against `MODAL_HTML` above. The stub returns what `extract` would, so what these checks see
# is what a real refusal prints.
TERMS_TEXT = EXTRACTED

BmdTerms.define_singleton_method(:text) { |_slug, **| TERMS_TEXT }

def refusal_error(release)
  strategy = BmdDownloadStrategy.new(
    "https://example.invalid/Test_1.0.zip", "test", "1.0", data: { "product" => "Test" }
  )
  strategy.send(:refuse_terms!, release)
  nil
rescue CurlDownloadStrategyError => e
  e
end

REFUSAL = refusal_error(release_with_terms("Blackmagic RAW 5.1", "bmd-braw-sdk-2")).freeze

check("refusing raises an error that exits non-zero") do
  REFUSAL.is_a?(CurlDownloadStrategyError) && REFUSAL.is_a?(RuntimeError)
end

check("the refusal displays the agreement itself, not the catalog's slug for it") do
  REFUSAL.message.include?(TERMS_TEXT) && !REFUSAL.message.match?(/^bmd-braw-sdk-2$/)
end

check("the refusal names the product") do
  REFUSAL.message.include?("Blackmagic RAW 5.1")
end

check("the refusal states the config path and the exact key to add") do
  REFUSAL.message.include?(BmdConfig.path.to_s) && REFUSAL.message.include?("\"agreeToTerms\": true")
end

check("the refusal says nothing was downloaded") do
  REFUSAL.message.include?("Nothing has been downloaded")
end

check("the refusal offers no way to accept other than the config file") do
  # An env-var escape hatch would make acceptance a throwaway flag on one command line rather than a
  # deliberate act recorded in a file the user wrote, and `accepts_terms?` does not honour one.
  REFUSAL.message.downcase.exclude?("environment variable") &&
    REFUSAL.message.exclude?(BmdConfig.env_var(BmdConfig::TERMS_FIELD))
end

puts "\nthe guard in _fetch"

# `refuse_terms!` above is the message; this is the decision to call it. Both directions are checked
# because either failure is silent in the other's tests: a broken guard downloads a gated release
# without consent, and an over-eager one refuses a release the user already agreed to.
#
# `mac_release` and `_curl_download` are stubbed — the first curls the catalog, the second the
# artifact — and `mint_signed_url` is replaced by a recorder, so what reaches Blackmagic is inspected
# rather than sent.
def fetch_attempt(release, terms_accepted)
  recorded = {}
  strategy = BmdDownloadStrategy.new(
    "https://example.invalid/Test_1.0.zip", "test", "1.0", data: { "product" => "Test" }
  )
  strategy.define_singleton_method(:mint_signed_url) do |id, registration:, terms: false, **|
    recorded.merge!(id:, registration:, terms:)
    "https://sw.blackmagicdesign.com/signed"
  end
  strategy.define_singleton_method(:_curl_download) { |*| recorded[:downloaded] = true }
  strategy.define_singleton_method(:quiet?) { true }
  BmdCatalog.define_singleton_method(:mac_release) { |_product, _version, **| release }

  with_terms_config(terms_accepted) do
    strategy.send(:_fetch, url: "https://example.invalid/Test_1.0.zip", resolved_url: nil, timeout: nil)
  end
  recorded
rescue CurlDownloadStrategyError => e
  recorded.merge(refused: e)
end

GATED = release_with_terms("Blackmagic RAW 5.1", "bmd-braw-sdk-2").freeze

check("refuses a gated release when the config carries no opt-in") do
  attempt = fetch_attempt(GATED, nil)
  attempt[:refused].is_a?(CurlDownloadStrategyError) && attempt[:downloaded].nil? && attempt[:id].nil?
end

check("downloads a gated release once the config carries the opt-in") do
  attempt = fetch_attempt(GATED, true)
  attempt[:refused].nil? && attempt[:downloaded] && attempt[:terms]
end

check("does not refuse an ungated release, and claims no agreement for it") do
  attempt = fetch_attempt(release_without_terms("Test 1.0"), nil)
  attempt[:refused].nil? && attempt[:downloaded] && attempt[:terms] == false
end

puts "\nwhat the resolve request asserts"

# Blackmagic's own modal sends `hasAgreedToTerms` from the checkbox on a gated release; the tap sends
# it from the config file, and only there. Asserting it for a release with no terms would be claiming
# agreement to a document that does not exist.
def body_for(terms:, registration: false)
  strategy = BmdDownloadStrategy.new(
    "https://example.invalid/Test_1.0.zip", "test", "1.0", data: { "product" => "Test" }
  )
  strategy.send(:request_body, registration:, terms:)
end

check("asserts agreement to Blackmagic for a gated release") do
  body_for(terms: true)["hasAgreedToTerms"] == true
end

check("asserts nothing about terms for an ungated release") do
  body_for(terms: false).exclude?("hasAgreedToTerms")
end

report_failures!
