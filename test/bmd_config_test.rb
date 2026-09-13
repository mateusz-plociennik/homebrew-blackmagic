# typed: false
# frozen_string_literal: true

# Tests for `BmdConfig`: which source wins per field, and that an incomplete config fails loudly
# rather than posting a partial registration to Blackmagic.
#
# Run with `brew ruby test/bmd_config_test.rb`. Plain assertions rather than a framework, for the
# reasons in `test/support.rb`.
#
# The loader reads `XDG_CONFIG_HOME`, so every case points it at a temporary directory — nothing here
# touches a real `~/.config/bmd-tap/config.json`, and nothing here contains anyone's real details.

require "tmpdir"

require_relative "../lib/bmd_config"
require_relative "support"

DETAILS = BmdConfig::REGISTRATION_FIELDS.to_h { |name| [name, "test-#{name}"] }.freeze

# Sets exactly `env` for the duration of the block and puts it back afterwards — a stray `BMD_TAP_*`
# in the developer's own shell must not be able to decide a result.
def with_env(env)
  previous = env.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
  env.each { |key, value| ENV[key] = value }
  yield
ensure
  previous&.each { |key, value| ENV[key] = value }
end

# A config directory holding `config` (nil for no file), with every `BMD_TAP_*` variable cleared and
# then `env` applied on top.
def with_config_dir(config, env: {}, &block)
  Dir.mktmpdir("bmd-config-test") do |dir|
    path = File.join(dir, "bmd-tap")
    Dir.mkdir(path)
    File.write(File.join(path, "config.json"), config) unless config.nil?

    cleared = BmdConfig::FIELDS.to_h { |name| [BmdConfig.env_var(name), nil] }
    with_env(cleared.merge("XDG_CONFIG_HOME" => dir).merge(env), &block)
  end
end

FULL_CONFIG = JSON.generate(DETAILS.merge("country" => "nz")).freeze

puts "\npath"

check("lives under XDG_CONFIG_HOME when that is set") do
  with_config_dir(nil) { BmdConfig.path.to_s.end_with?("/bmd-tap/config.json") }
end

puts "\ncountry"

# The whole point of a default: an anonymous-path cask must install on a machine with no config file.
check("defaults to au with no config file and no environment") do
  with_config_dir(nil) { BmdConfig.country == "au" }
end

check("comes from the config file when set there") do
  with_config_dir(FULL_CONFIG) { BmdConfig.country == "nz" }
end

check("prefers the environment over the file") do
  with_config_dir(FULL_CONFIG, env: { "BMD_TAP_COUNTRY" => "gb" }) { BmdConfig.country == "gb" }
end

check("falls back to the default when the file says nothing about it") do
  with_config_dir(JSON.generate(DETAILS)) { BmdConfig.country == "au" }
end

puts "\nregistration_details"

check("returns every field Blackmagic ask for") do
  with_config_dir(FULL_CONFIG) { BmdConfig.registration_details == DETAILS }
end

# `country` travels in the anonymous half of the body already, so it must not be duplicated here.
check("does not include country") do
  with_config_dir(FULL_CONFIG) { BmdConfig.registration_details.keys.exclude?("country") }
end

check("takes a single field from the environment over the file") do
  with_config_dir(FULL_CONFIG, env: { "BMD_TAP_EMAIL" => "env@example.com" }) do
    BmdConfig.registration_details["email"] == "env@example.com"
  end
end

# CI supplies everything through the environment, with no file on disk at all.
check("works from the environment alone") do
  env = DETAILS.to_h { |name, value| [BmdConfig.env_var(name), value] }
  with_config_dir(nil, env:) { BmdConfig.registration_details == DETAILS }
end

check("strips surrounding whitespace") do
  with_config_dir(JSON.generate(DETAILS.merge("email" => "  spaced@example.com  "))) do
    BmdConfig.registration_details["email"] == "spaced@example.com"
  end
end

puts "\nregistration_details failures"

# The error is the entire user interface for this file, so it has to name the path, the JSON to write
# and which fields were missing — a bare "registration required" leaves someone guessing at a filename.
check_raises("names the config path when no file exists", BmdConfig::ConfigError, "bmd-tap/config.json") do
  with_config_dir(nil) { BmdConfig.registration_details }
end

check_raises("prints the JSON skeleton", BmdConfig::ConfigError, '"firstname"') do
  with_config_dir(nil) { BmdConfig.registration_details }
end

check_raises("names an environment variable as the alternative", BmdConfig::ConfigError, "BMD_TAP_") do
  with_config_dir(nil) { BmdConfig.registration_details }
end

check_raises("names the fields that are missing", BmdConfig::ConfigError, "phone, city") do
  with_config_dir(JSON.generate(DETAILS.merge("phone" => "", "city" => nil))) do
    BmdConfig.registration_details
  end
end

# A blank string is what a half-filled skeleton looks like, and posting it would register someone with
# an empty surname rather than fail.
check_raises("treats a whitespace-only value as missing", BmdConfig::ConfigError, "lastname") do
  with_config_dir(JSON.generate(DETAILS.merge("lastname" => "   "))) { BmdConfig.registration_details }
end

puts "\nblank overrides"

# An empty `BMD_TAP_*` is what an unset CI secret expands to, so it counts as absent rather than as an
# override to a blank value: the file still answers, and if neither source has the field the missing-
# field error above is what surfaces. Never a blank field posted to Blackmagic either way.
check("ignores a blank environment override in favour of the file") do
  with_config_dir(FULL_CONFIG, env: { "BMD_TAP_EMAIL" => "" }) do
    BmdConfig.registration_details["email"] == DETAILS["email"]
  end
end

check_raises("still fails when a blank override is the only source", BmdConfig::ConfigError, "email") do
  with_config_dir(JSON.generate(DETAILS.except("email")), env: { "BMD_TAP_EMAIL" => "  " }) do
    BmdConfig.registration_details
  end
end

check_raises("rejects a non-string value", BmdConfig::ConfigError, "must be a JSON string") do
  with_config_dir(JSON.generate(DETAILS.merge("phone" => 5_551_234))) { BmdConfig.registration_details }
end

check_raises("rejects invalid JSON", BmdConfig::ConfigError, "not valid JSON") do
  with_config_dir("{ not json") { BmdConfig.registration_details }
end

check_raises("rejects a JSON array", BmdConfig::ConfigError, "must contain a JSON object") do
  with_config_dir("[]") { BmdConfig.registration_details }
end

# An unreadable file must not take the anonymous path down with it — but it must not be ignored either.
check_raises("surfaces a broken file even for country", BmdConfig::ConfigError, "not valid JSON") do
  with_config_dir("{ not json") { BmdConfig.country }
end

puts "\nskeleton"

check("carries the real default for country") { BmdConfig.skeleton.include?('"country": "au"') }
check("lists every field the loader reads") do
  BmdConfig::FIELDS.all? { |name| BmdConfig.skeleton.include?(name.inspect) }
end

puts "\naccepts_terms?"

check("returns false when the config file does not exist") do
  with_config_dir(nil) { !BmdConfig.accepts_terms? }
end

check("returns false when agreeToTerms is not in the config") do
  with_config_dir(FULL_CONFIG) { !BmdConfig.accepts_terms? }
end

check("returns true when agreeToTerms is set to true") do
  config_with_terms = JSON.generate(DETAILS.merge("country" => "nz", "agreeToTerms" => true))
  with_config_dir(config_with_terms) { BmdConfig.accepts_terms? }
end

check("returns false when agreeToTerms is set to false") do
  config_with_false = JSON.generate(DETAILS.merge("country" => "nz", "agreeToTerms" => false))
  with_config_dir(config_with_false) { !BmdConfig.accepts_terms? }
end

check("returns false when agreeToTerms is a string") do
  config_with_string = JSON.generate(DETAILS.merge("country" => "nz", "agreeToTerms" => "true"))
  with_config_dir(config_with_string) { !BmdConfig.accepts_terms? }
end

check("ignores an environment variable for agreeToTerms (only file matters)") do
  config_no_terms = JSON.generate(DETAILS.merge("country" => "nz"))
  # Derived, not spelled out: a typo'd name here would pass whether or not `accepts_terms?` reads the
  # environment, which is the whole guarantee this check exists to hold.
  env = { BmdConfig.env_var(BmdConfig::TERMS_FIELD) => "true" }
  with_config_dir(config_no_terms, env:) { !BmdConfig.accepts_terms? }
end

report_failures!
