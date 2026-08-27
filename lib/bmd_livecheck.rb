# typed: false
# frozen_string_literal: true

require_relative "bmd_download_strategy"

# Shared `livecheck` plumbing for the Blackmagic casks.
#
# Blackmagic do expose a version-pointer endpoint
# (`/api/support/latest-stable-version/{product}/mac`), but it is keyed on the catalog's `product`
# slug, and that slug is a *product family*, not a product: Blackmagic Ethernet Switch and Blackmagic
# Videohub both live under `videohub`, and the pointer answers with Videohub's release. Nothing in
# the endpoint distinguishes them, and an unknown slug is indistinguishable from a known one
# (`{"mac":null}` either way), so the pointer cannot be used to identify a specific product.
#
# The release catalog is the only endpoint that enumerates releases. It is what Blackmagic's own
# support page fetches to render its "Latest Downloads" list — that page is entirely client-rendered,
# so there is no lighter list to read. It is ~1.5 MB of JSON, served gzipped at ~226 KB behind a
# 15-minute cache, and no HTML is parsed.
module BmdLivecheck
  # Releases are the same worldwide, so the country segment only affects fields livecheck ignores.
  # It is not read from `BMD_TAP_COUNTRY`: this URL is what livecheck reports on failure, and it
  # should not vary by environment.
  CATALOG_URL = "https://www.blackmagicdesign.com/api/support/" \
                "#{BmdDownloadStrategy::DEFAULT_COUNTRY}/downloads.json".freeze

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
      next if release.dig("urls", "Mac OS X").blank?

      name = release["name"]
      next if name.blank?

      name[regex, 1]
    end
  end.freeze
end
