# typed: false
# frozen_string_literal: true

require "json"
require "utils/curl"

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
  DEFAULT_COUNTRY = "au"
  URL_TEMPLATE = "https://www.blackmagicdesign.com/api/support/%<country>s/downloads.json"

  # The URL `livecheck` reads. Deliberately not `country` — livecheck reports this string on failure,
  # and diagnostics should not vary by environment.
  CATALOG_URL = format(URL_TEMPLATE, country: DEFAULT_COUNTRY).freeze

  PLATFORM = "Mac OS X"

  # Versions of every catalog release that ships a macOS build and whose *entire* name matches the
  # cask's regex.
  #
  # The anchoring is the point. Blackmagic distinguish separate products by suffixing the release
  # name — `DaVinci Resolve 21.0.4 Update` and `DaVinci Resolve Studio 21.0.4 Update` are different
  # products, older Studio releases were named `DaVinci Resolve 15.3 Studio`, and there are `SDK`
  # and `Public Beta` releases under otherwise identical names. A regex anchored at both ends forces
  # each cask to spell out the name shape it accepts, so it cannot silently inherit a sibling
  # product's version. Pass it a full-name pattern, not a prefix.
  MAC_RELEASES = proc do |json, regex|
    json["downloads"]&.map do |release|
      next if release.dig("urls", PLATFORM).blank?

      name = release["name"]
      next if name.blank?

      name[regex, 1]
    end
  end.freeze

  class << self
    def country
      ENV.fetch("BMD_TAP_COUNTRY", DEFAULT_COUNTRY)
    end

    # The `downloadId` for a release's macOS build, looked up by the release's exact catalog name.
    #
    # Two distinct id namespaces live in the catalog: `id` is the release GUID that appears in the
    # web page path, one per release across all platforms, and `downloadId` is per
    # *(release × platform)* and is the only one the resolve endpoint accepts — posting a release id
    # returns `400 The download id '…' was not found`.
    #
    # Raises rather than returning nil: this runs before any bytes move, and every caller needs the
    # id. The message names what was looked for, because the likely cause is upstream renaming a
    # release rather than the id going away.
    def mac_download_id(name, timeout: nil)
      release = releases(timeout:).find { |entry| entry["name"] == name }

      raise CatalogError, <<~MESSAGE if release.nil?
        Blackmagic's catalog has no release named "#{name}".

        The cask pins that name; upstream has most likely renamed or withdrawn the release. Compare
        against #{CATALOG_URL} and update the cask.
      MESSAGE

      download_id = release.dig("urls", PLATFORM)&.first&.fetch("downloadId", nil)

      raise CatalogError, <<~MESSAGE if download_id.blank?
        Blackmagic's catalog lists "#{name}" but no #{PLATFORM} build for it.
      MESSAGE

      download_id
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
