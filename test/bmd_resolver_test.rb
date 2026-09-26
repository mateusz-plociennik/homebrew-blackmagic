# typed: false
# frozen_string_literal: true

# Tests for `BmdResolver` — the resolve POST both the install path and the generator make.
#
# Run with `brew ruby test/bmd_resolver_test.rb`. Plain assertions rather than a framework.
#
# The request itself is not sent: `Utils::Curl.curl_output` is stubbed, so these cover the body the
# tap would post and the refusal it would raise. Everything asserted here was established against
# Blackmagic empirically — the notes live in `lib/bmd_resolver.rb`, and this file is what stops a
# change to any of it going unnoticed on one of the two callers.

require_relative "../lib/bmd_resolver"
require_relative "support"

# `SystemCommand::Result`'s own shape, with only what `mint_signed_url` reads.
CurlResult = Struct.new(:stdout, :success) do
  def success? = success
  def status = Struct.new(:exitstatus).new(7)
end

def resolving(stdout, success: true)
  recorded = {}
  Utils::Curl.define_singleton_method(:curl_output) do |*args, **options|
    recorded[:args] = args
    recorded[:options] = options
    CurlResult.new(stdout, success)
  end

  url = BmdResolver.mint_signed_url("download-id", product: "Test", registration: false)
  recorded.merge(url:)
rescue BmdResolver::RefusedError => e
  recorded.merge(refused: e)
end

SIGNED = "https://sw.blackmagicdesign.com/Test.zip?Signature=abc"
RESOLVED = resolving(SIGNED).freeze

puts "\nthe request the tap posts"

check("returns Blackmagic's plain-text body as the signed URL") { RESOLVED[:url] == SIGNED }

check("posts to the country-scoped resolve endpoint for the download id") do
  RESOLVED[:args].last == "https://www.blackmagicdesign.com/api/register/#{BmdCatalog.country}/download/download-id"
end

# Blackmagic answer 400 to any User-Agent containing "curl", which Homebrew's default ends in, and
# the POST registers a download — a retry would register a second one.
check("sends no User-Agent, and never retries") do
  RESOLVED[:options][:user_agent] == "" && RESOLVED[:options][:retries].zero?
end

puts "\nthe two body shapes"

# The registration fields come from the environment so this runs the same with or without a config
# file on the machine — CI has none, and it must still see the registration body.
def with_registration_details
  overrides = BmdConfig::REGISTRATION_FIELDS.to_h { |name| [BmdConfig.env_var(name), "test-#{name}"] }
  previous = overrides.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
  overrides.each { |key, value| ENV[key] = value }

  yield
ensure
  previous&.each { |key, value| ENV[key] = value }
end

ANONYMOUS = BmdResolver.request_body(product: "Test", registration: false).freeze
REGISTRATION = with_registration_details { BmdResolver.request_body(product: "Test", registration: true) }.freeze

check("names no product on the anonymous path, which is what makes it anonymous") do
  ANONYMOUS.exclude?("product") && ANONYMOUS["downloadOnly"] == true
end

check("names the product on the registration path, and drops downloadOnly") do
  REGISTRATION["product"] == "Test" && REGISTRATION.exclude?("downloadOnly")
end

# The country appears in the path as well; omitting it from the body is a 400 either way.
check("carries the country in the body as well as the path") do
  ANONYMOUS["country"] == BmdCatalog.country && REGISTRATION["country"] == BmdCatalog.country
end

puts "\nwhen Blackmagic refuse"

REFUSED = resolving("Must register to download this", success: true).freeze

check("raises rather than handing back a non-URL response") do
  REFUSED[:refused].is_a?(BmdResolver::RefusedError)
end

check("quotes Blackmagic's own words back") do
  REFUSED[:refused].message.include?("Must register to download this")
end

# Their wording names nothing anyone can act on; the config file is the actionable part.
check("names the config file when the refusal is about registration") do
  REFUSED[:refused].message.include?(BmdConfig.path.to_s)
end

check("says the request is not retried, because it registered a download") do
  REFUSED[:refused].message.include?("not retried automatically")
end

check("carries the endpoint separately, for a caller that needs the URL") do
  REFUSED[:refused].endpoint.include?("/download/download-id")
end

check("reports curl's exit status when Blackmagic said nothing at all") do
  resolving("", success: false)[:refused].message.include?("curl exited 7")
end

report_failures!
