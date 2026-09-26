# typed: false
# frozen_string_literal: true

require "json"
require "utils/curl"

require_relative "bmd_config"

# Blackmagic's release catalog — the tap's single source of truth for what upstream ships.
#
# `GET /api/support/{country}/downloads.json` is the only endpoint that enumerates releases, and it
# enumerates *all* of them: ~1220 entries going back years, so a cask pinned behind the current
# release is still in there. It is what Blackmagic's own support page fetches to render its "Latest
# Downloads" list — that page is entirely client-rendered, so there is nothing lighter to read.
# ~1.5 MB of JSON, served gzipped at ~226 KB behind a 15-minute cache.
#
# Blackmagic do also expose a version-pointer endpoint
# (`/api/support/latest-stable-version/{product}/mac`), but it is keyed on the catalog's `product`
# slug, and that slug is a product *family*, not a product: Blackmagic Ethernet Switch and Blackmagic
# Videohub both live under `videohub`, and the pointer answers with Videohub's release. Nothing in the
# endpoint distinguishes them, and an unknown slug is indistinguishable from a known one
# (`{"mac":null}` with a 200 either way), so the pointer cannot identify a specific product.
#
# Unlike the resolve endpoint on the same host, this one does not filter on User-Agent — Homebrew's
# own UA and curl's default both get a 200 — so no override is needed here.
module BmdCatalog
  # Releases are the same worldwide; the country segment only affects fields the tap ignores.
  DEFAULT_COUNTRY = BmdConfig::DEFAULT_COUNTRY
  URL_TEMPLATE = "https://www.blackmagicdesign.com/api/support/%<country>s/downloads.json"

  # The URL `livecheck` reads. Deliberately not `country` — livecheck reports this string on failure,
  # and diagnostics should not vary by environment.
  CATALOG_URL = format(URL_TEMPLATE, country: DEFAULT_COUNTRY).freeze

  PLATFORM = "Mac OS X"

  # A version, as Blackmagic write one in a release name: one to four dot-separated numbers, from
  # `DaVinci Resolve Project Server 21` through `Blackmagic Camera 9.9.1`.
  VERSION_PATTERN = '\d+(?:\.\d+)*'

  # The only trailing word a release name may carry and still be the same product.
  #
  # Blackmagic ship a product's first release of a series under a bare name and its point releases
  # under ` Update` — `Blackmagic Camera 10.2` then `Blackmagic Camera 10.2.2 Update` — so a pattern
  # that accepts only the bare shape sees a product's history stop at its last bare release. That is
  # silent: livecheck reports the stale version as current, `brew bump` finds nothing to do, and the
  # cask stays frozen. Every product in this tap except Ethernet Switch and Cloud Store point-releases
  # this way.
  #
  # Nothing else belongs here. ` SDK` builds are developer libraries rather than apps, ` Beta` and
  # ` Public Beta` are a channel this tap does not ship, and ` Studio` marks a separate paid product.
  OPTIONAL_SUFFIX = "(?: Update)?"

  # The pattern a cask's release names must match, anchored at both ends.
  #
  # Anchoring is what keeps products apart, and it earns its keep in both directions. `DaVinci
  # Resolve` must not match `DaVinci Resolve Studio 21.0.4 Update` (a different product, leading
  # extra word) nor `DaVinci Resolve 15.3 Studio` (the same product's pre-16 naming, trailing extra
  # word), and `Blackmagic RAW` must not match `Blackmagic RAW Player 1.4`. Capture group 1 is the
  # version, which is what `MAC_RELEASES` hands back to livecheck.
  #
  # Casks call this rather than writing the regex out, so the set of accepted suffixes is defined
  # once. A cask spelling its own regex would drift from `find_mac_release` below, and the two
  # disagreeing is exactly the failure this replaced: a livecheck that reports a version the lookup
  # then cannot resolve.
  def self.release_regex(product)
    /\A#{Regexp.escape(product)} (#{VERSION_PATTERN})#{OPTIONAL_SUFFIX}\z/
  end

  # Versions of every catalog release that ships a macOS build and whose *entire* name matches the
  # cask's regex. Pass a pattern from `release_regex`, never a prefix.
  MAC_RELEASES = proc do |json, regex|
    json["downloads"]&.map do |release|
      next if release.dig("urls", PLATFORM).blank?

      name = release["name"]
      next if name.blank?

      name[regex, 1]
    end
  end.freeze

  class << self
    # Delegated so the country the catalog is read from and the country a download is registered in
    # cannot disagree; `BmdConfig` owns both the default and the `BMD_TAP_COUNTRY` override.
    #
    # Kept as a delegate rather than having callers reach for `BmdConfig.country` because the country
    # is a path segment on the catalog *and* resolve URLs, and both are read from here. This is the
    # only hop — `BmdResolver` is the one caller, and nothing wraps it again.
    def country
      BmdConfig.country
    end

    # The `downloadId` for the macOS build of a product's release, looked up by product name and
    # version.
    #
    # Two distinct id namespaces live in the catalog: `id` is the release GUID that appears in the
    # web page path, one per release across all platforms, and `downloadId` is per
    # *(release × platform)* and is the only one the resolve endpoint accepts — posting a release id
    # returns `400 The download id '…' was not found`.
    #
    # Keyed on the version rather than on the full release name because a cask holds only the
    # version: `brew bump-cask-pr` rewrites `version`, `url` and `sha256` and nothing else, so a cask
    # that spelled out `"Blackmagic Camera 10.2 Update"` would still be spelling out `10.2` after a
    # bump to `10.2.2`, and `_fetch` would download the old artifact under the new version's name.
    def mac_download_id(product, version, timeout: nil)
      mac_download_id_from(releases(timeout:), product, version)
    end

    # The whole catalog entry for a product's release, fetched fresh. What `BmdDownloadStrategy` reads:
    # the entry carries both the download id and the `requiresRegistration` /
    # `requiresTermsAndConditions` flags that decide which request body Blackmagic will accept, so
    # taking the entry rather than just the id means no cask has to restate a flag that upstream owns
    # and can change under it.
    def mac_release(product, version, timeout: nil)
      find_mac_release(releases(timeout:), product, version)
    end

    # The macOS `downloadId` on an entry already in hand. Present on every entry `find_mac_release`
    # returns — it refuses the ones without.
    def download_id_for(release)
      release.dig("urls", PLATFORM).first.fetch("downloadId")
    end

    # Whether Blackmagic will reject an anonymous request for this release and demand a full set of
    # identity fields (a `403 Must register to be able to perform the download`).
    def requires_registration?(release)
      release["requiresRegistration"].present?
    end

    # Whether the release additionally requires accepting a licence agreement. `_fetch` refuses these
    # unless the config file carries an explicit opt-in (#6) — never agreeing on the user's behalf.
    def requires_terms?(release)
      release["requiresTermsAndConditions"].present?
    end

    # `mac_download_id` against an already-fetched catalog. Split out so the matching rules can be
    # tested without curling 1.5 MB from Blackmagic; see `test/bmd_catalog_test.rb`.
    def mac_download_id_from(releases, product, version)
      download_id_for(find_mac_release(releases, product, version))
    end

    # The one release of `product` at `version` that ships a macOS build.
    #
    # Raises rather than returning nil in every failure mode: this runs before any bytes move, and
    # every caller needs an id. The messages name what was looked for, since the likely cause is
    # upstream renaming or withdrawing a release rather than an id going away.
    def find_mac_release(releases, product, version)
      pattern = release_regex(product)
      matches = releases.select { |entry| entry["name"].to_s.match?(pattern) && entry["name"][pattern, 1] == version }

      raise CatalogError, <<~MESSAGE if matches.empty?
        Blackmagic's catalog has no release "#{product} #{version}".

        The cask pins that product and version; upstream has most likely renamed or withdrawn the
        release. Compare against #{CATALOG_URL} and update the cask.
      MESSAGE

      # Not reachable against today's catalog — no (product, version) pair carries both a bare and an
      # ` Update` name. If upstream ever ships both, picking one by position would pin a `sha256`
      # against whichever the catalog happened to list first, so refuse and name them instead.
      raise CatalogError, <<~MESSAGE if matches.length > 1
        "#{product} #{version}" matches #{matches.length} releases in Blackmagic's catalog:
        #{matches.map { |entry| "  #{entry["name"]}" }.join("\n")}

        Ambiguous, so nothing was downloaded. #{CATALOG_URL}
      MESSAGE

      release = matches.first
      return release if release.dig("urls", PLATFORM)&.first&.fetch("downloadId", nil).present?

      raise CatalogError, <<~MESSAGE
        Blackmagic's catalog lists "#{release["name"]}" but no #{PLATFORM} build for it.
      MESSAGE
    end

    private

    def releases(timeout: nil)
      url = format(URL_TEMPLATE, country:)
      result = Utils::Curl.curl_output("--compressed", url, timeout:)

      raise CatalogError, <<~MESSAGE unless result.success?
        Could not read Blackmagic's release catalog at #{url}
        (curl exited #{result.status.exitstatus}).
      MESSAGE

      downloads = JSON.parse(result.stdout)["downloads"]
      raise CatalogError, "Blackmagic's release catalog at #{url} has no `downloads` array." if downloads.blank?

      downloads
    rescue JSON::ParserError => e
      raise CatalogError, "Blackmagic's release catalog at #{url} is not valid JSON: #{e.message}"
    end
  end

  # Raised for every way the catalog can fail to name an artifact. Subclasses `RuntimeError` rather
  # than one of Homebrew's download errors because the lookup is not itself a download.
  class CatalogError < RuntimeError; end
end
