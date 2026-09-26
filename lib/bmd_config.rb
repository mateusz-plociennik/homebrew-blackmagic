# typed: false
# frozen_string_literal: true

require "json"

# The user's own Blackmagic registration details, read from `~/.config/bmd-tap/config.json`.
#
# Roughly two thirds of Blackmagic's catalog resolves anonymously; those downloads need nothing from
# this file, and `country` — the only field the anonymous path sends — defaults to `au`. So the
# common case stays zero-setup, and only registration-gated releases (see
# `requiresRegistration` in `BmdCatalog`) ever require a config file. Preserving that split is
# deliberate: do not make every install depend on configuration.
#
# The tap ships no identity defaults and fabricates nothing. When a download requires registration,
# the request submitted is *the user's* registration with Blackmagic, and the tap is merely their HTTP
# client — a placeholder value here would misrepresent a real person to a vendor. Hence: every
# registration field must be supplied, blanks are treated as absent, and a missing field is a
# fail-fast error naming the path and the JSON to write rather than a prompt or a guess.
#
# XDG rather than a dotfile in `$HOME`, so a sibling cache directory has somewhere to live later.
# `XDG_CONFIG_HOME` is honoured where set, which is also how the tests point the loader at a
# temporary directory.
#
# Every field is overridable by a `BMD_TAP_`-prefixed environment variable, so CI (and a one-off
# install with different details) needs no file at all. The environment wins over the file: it is the
# more specific, more deliberate of the two.
module BmdConfig
  # Blackmagic's `country` is a URL path segment on their API, and releases are the same worldwide —
  # it selects which regional Blackmagic entity the registration goes to, not which artifact.
  DEFAULT_COUNTRY = "au"

  RELATIVE_PATH = "bmd-tap/config.json"
  ENV_PREFIX = "BMD_TAP_"

  COUNTRY_FIELD = "country"
  TERMS_FIELD = "agreeToTerms"

  # What Blackmagic's resolve endpoint demands of a `requiresRegistration` release, on top of the
  # anonymous body. All of them: the endpoint 400s on a partial set, and it is the same set their own
  # web form asks for.
  REGISTRATION_FIELDS = %w[firstname lastname email phone company street city state].freeze

  FIELDS = [COUNTRY_FIELD, *REGISTRATION_FIELDS].freeze

  # Raised for every way the config file can fail to answer. Subclasses `RuntimeError` so it surfaces
  # as a plain `Error:` line under `brew install` and exits non-zero, like `BmdCatalog::CatalogError`.
  class ConfigError < RuntimeError; end

  class << self
    def path
      base = ENV.fetch("XDG_CONFIG_HOME", nil).presence || File.expand_path("~/.config")
      Pathname(base)/RELATIVE_PATH
    end

    # The country segment for Blackmagic's API. Always answers — this is the one field with a
    # default, which is what keeps anonymous casks installable with no config file present.
    def country
      field(COUNTRY_FIELD).presence || DEFAULT_COUNTRY
    end

    # Every registration field, ready to merge into a resolve request body. Raises rather than
    # returning a partial set: this runs before any bytes move, and a body missing a field is a 400
    # from Blackmagic that says nothing about which field.
    def registration_details
      values = REGISTRATION_FIELDS.to_h { |name| [name, field(name)] }
      missing = values.select { |_, value| value.blank? }.keys
      raise ConfigError, missing_message(missing) if missing.any?

      values
    end

    # Whether the user has explicitly opted into accepting terms and conditions.
    # Acceptance is never inferred: it must be an explicit key in the config, and the value must be
    # `true` (not just any truthy value, not a string, literally the JSON boolean true).
    #
    # Deliberately not `field` — this is the one setting the environment cannot supply. Accepting a
    # licence on the user's behalf should be an act they performed once in a file they wrote, not a
    # variable that can ride along on a single `brew install` line or be exported by a script.
    def accepts_terms?
      file_data[TERMS_FIELD] == true
    end

    # One field, environment first. `nil` when neither source has it — callers decide whether that is
    # fatal, since `country` tolerates absence and the registration fields do not.
    def field(name)
      env = ENV.fetch(env_var(name), nil)
      return env.strip if env.present?

      value = file_data[name]
      return if value.nil?

      unless value.is_a?(String)
        raise ConfigError, "#{path}: #{name.inspect} must be a JSON string, got #{value.class}."
      end

      value.strip.presence
    end

    def env_var(name)
      "#{ENV_PREFIX}#{name.upcase}"
    end

    # The JSON skeleton the error messages print. Built from `FIELDS` so it cannot drift from what
    # the loader actually reads — and carrying the real default for `country`, since that one is not a
    # value the user has to invent.
    def skeleton
      body = FIELDS.map do |name|
        value = (name == COUNTRY_FIELD) ? DEFAULT_COUNTRY : "…"
        "  #{name.inspect}: #{value.inspect}"
      end
      "{\n#{body.join(",\n")}\n}"
    end

    private

    def file_data
      return {} unless path.exist?

      data = JSON.parse(path.read)
      raise ConfigError, "#{path} must contain a JSON object, got #{data.class}." unless data.is_a?(Hash)

      data
    rescue JSON::ParserError => e
      raise ConfigError, "#{path} is not valid JSON: #{e.message}"
    end

    def missing_message(missing)
      <<~MESSAGE
        This download requires registration with Blackmagic Design, and #{missing.length} of the
        details they ask for #{(missing.length == 1) ? "is" : "are"} not configured: #{missing.join(", ")}.

        Write #{path} with your own real details:

        #{skeleton}

        Any field can also be supplied by an environment variable instead — #{env_var(missing.first)},
        and so on for the rest — which is how this works in CI without a config file.

        Use your real details. This request registers *you* with Blackmagic; the tap is only your HTTP
        client, and it ships no defaults. Nothing has been downloaded.
      MESSAGE
    end
  end
end
