# typed: false
# frozen_string_literal: true

# Homebrew's own download strategies are `# typed: strict`, but they live inside the Homebrew
# checkout that `srb` typechecks. Nothing typechecks `Library/Taps`, so a stricter sigil here would
# claim a guarantee no tool verifies, while a wrong `sig` still fails at runtime — inside
# `brew install`. The `sig` below is kept because sorbet-runtime does enforce it on every call.

require "download_strategy"

require_relative "bmd_catalog"
require_relative "bmd_config"
require_relative "bmd_resolver"
require_relative "bmd_terms"

# Downloads Blackmagic Design installers.
#
# Blackmagic serve their artifacts from CloudFront behind signed URLs that expire after roughly an
# hour, and the unsigned path 404s — so there is no durable URL a cask can hold. This strategy POSTs
# to Blackmagic's download endpoint at fetch time to mint a fresh signed URL, then downloads that.
#
# The cask's `url` stanza holds the stable *unsigned* path, which is never actually requested.
# Homebrew keys its download cache on a hash of that string (see
# `AbstractFileDownloadStrategy#cached_location`), so keeping it stable is what makes caching work at
# all: a signed URL, whose signature differs on every mint, would produce a fresh multi-hundred-
# megabyte cache entry per fetch and would defeat `brew fetch` followed by `brew install`.
#
# The endpoint takes a `downloadId`, which is per *(release × platform)* and opaque. Casks do not hold
# it: they name the release, and the id is looked up in the catalog at fetch time (see `BmdCatalog`).
# Pinning the id instead would let `brew bump-cask-pr` — which rewrites only `version`, `url` and
# `sha256` — produce a cask whose version says 1.3 while the id still fetches 1.2, and since `_fetch`
# ignores `url` entirely, the bytes would follow the stale id. That failure is silent: the checksum it
# computes belongs to the artifact it actually downloaded.
#
# The product name travels in the cask's `data:` stanza; the version comes from the cask's `version`
# stanza, which is where Homebrew already keeps it. Only `CurlPostDownloadStrategy` ever reads
# `meta[:data]` (to build POST parameters); under `CurlDownloadStrategy` the key is inert, so it is
# free to carry our own metadata. Do not combine a `data:` stanza with `using: :post` in this tap.
#
# The product is named rather than the whole release because release names carry an optional ` Update`
# suffix on point releases that a cask cannot derive from its version — see `BmdCatalog::OPTIONAL_SUFFIX`.
#
# Which request body the endpoint will accept also comes from that catalog entry: `requiresRegistration`
# releases need the user's identity fields, read from `BmdConfig`, and anonymous ones need nothing.
# Casks state neither, so a release that changes flag upstream changes behaviour here without a cask
# edit — and casks on the anonymous path stay installable with no configuration at all.
class BmdDownloadStrategy < CurlDownloadStrategy
  sig { params(url: String, name: String, version: T.untyped, meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    super
    @product = meta.dig(:data, "product")
    return if @product.present?

    raise ArgumentError, "#{self.class.name} requires a `data: { \"product\" => \"...\" }` stanza"
  end

  private

  # Skip Homebrew's pre-flight HEAD request. It would probe the unsigned URL, which 404s by design.
  # Reporting the unsigned URL as its own resolution keeps both the cache key and the basename
  # derived from the stable path; `_fetch` ignores `resolved_url` and downloads a freshly signed one.
  # The trailing `nil`s are last-modified and content-length, which Homebrew only uses for cache
  # freshness heuristics — the pinned `sha256` is the real integrity check.
  #
  # Do not "fix" this override to restore the probe. It is load-bearing for the cache key, not for
  # audit: `brew audit --cask --online` passes for casks using this strategy, because
  # `Cask::Audit#audit_url_https_availability` returns early for any `url` with a `using:` strategy,
  # so the unsigned path is never validated. Its `audit_download` step then fetches through `_fetch`,
  # which mints a real signed URL — meaning an online audit downloads the whole artifact.
  def resolve_url_basename_time_file_size(url, timeout: nil)
    [url, parse_basename(url), nil, nil, nil, false]
  end

  def _fetch(url:, resolved_url:, timeout:)
    release = BmdCatalog.mac_release(@product, version.to_s, timeout:)
    terms = BmdCatalog.requires_terms?(release)
    refuse_terms!(release, timeout:) if terms && !BmdConfig.accepts_terms?
    registration = BmdCatalog.requires_registration?(release)

    signed_url = BmdResolver.mint_signed_url(BmdCatalog.download_id_for(release), product: @product,
                                             registration:, terms:, timeout:)
    ohai "Minted a signed URL from #{BmdResolver::SITE}" unless quiet?
    _curl_download signed_url, temporary_path, timeout
  rescue BmdResolver::RefusedError => e
    raise CurlDownloadStrategyError.new(e.endpoint, e.message)
  end

  # Some releases require accepting a licence agreement. If the user has granted explicit opt-in
  # in their config, we proceed; otherwise we refuse before any bytes move, displaying the agreement
  # itself and the exact config change needed. The check reads upstream's flag rather than a cask
  # attribute, so a release that gains terms after its cask was written stops working instead of
  # silently agreeing.
  #
  # The catalog entry names the agreement rather than carrying it, so the text is fetched — see
  # `BmdTerms`. If that fetch fails, `BmdTerms` raises and the install stops there: still a refusal,
  # which is the safe direction, and never a demand to agree to a document we could not show.
  def refuse_terms!(release, timeout: nil)
    terms_text = BmdTerms.text(release["termsAndConditions"], timeout:)

    message = "\"#{release["name"]}\" requires accepting Blackmagic Design's licence agreement.\n\n"
    message << "#{terms_text}\n\n"
    message << "(#{BmdTerms.url(release["termsAndConditions"])})\n\n"
    message << "If you agree to it, record that in #{BmdConfig.path}:\n\n"
    message << "{ \"agreeToTerms\": true }\n\n"
    message << "Nothing has been downloaded."

    raise CurlDownloadStrategyError.new(BmdResolver::SITE, message)
  end
end
