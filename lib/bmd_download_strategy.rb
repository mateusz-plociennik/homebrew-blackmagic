# typed: false
# frozen_string_literal: true

# Homebrew's own download strategies are `# typed: strict`, but they live inside the Homebrew
# checkout that `srb` typechecks. Nothing typechecks `Library/Taps`, so a stricter sigil here would
# claim a guarantee no tool verifies, while a wrong `sig` still fails at runtime — inside
# `brew install`. The `sig` below is kept because sorbet-runtime does enforce it on every call.

require "download_strategy"
require "json"

require_relative "bmd_catalog"
require_relative "bmd_config"
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
  RESOLVE_ENDPOINT = "https://www.blackmagicdesign.com/api/register/%<country>s/download/%<id>s"
  SITE = "https://www.blackmagicdesign.com"

  # Blackmagic's resolve endpoint answers `400 Bad Request` to any request whose User-Agent contains
  # the substring "curl" — a filter on the name alone, not on the client. Homebrew's default User-Agent
  # ends in `curl/8.7.1`, so leaving it in place fails every fetch with a bare "Bad Request" that
  # looks like throttling or a malformed body. Sending no User-Agent at all is accepted. Only the
  # resolve POST is affected; the artifact host (`sw.blackmagicdesign.com`) does not filter.
  USER_AGENT = ""

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
    refuse_terms!(release, timeout:) if BmdCatalog.requires_terms?(release) && !BmdConfig.accepts_terms?
    registration = BmdCatalog.requires_registration?(release)

    signed_url = mint_signed_url(BmdCatalog.download_id_for(release), registration:, timeout:)
    ohai "Minted a signed URL from #{SITE}" unless quiet?
    _curl_download signed_url, temporary_path, timeout
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

    message = +"\"#{release["name"]}\" requires accepting Blackmagic Design's licence agreement.\n\n"
    message << "#{terms_text}\n\n"
    message << "(#{BmdTerms.url(release["termsAndConditions"])})\n\n"
    message << "If you agree to it, record that in #{BmdConfig.path}:\n\n"
    message << "{ \"agreeToTerms\": true }\n\n"
    message << "Nothing has been downloaded."

    raise CurlDownloadStrategyError.new(SITE, message)
  end

  # Ask Blackmagic for a signed URL. Returns it as a bare string — the endpoint answers with the URL
  # as its plain-text body, not JSON.
  #
  # `retries: 0` is deliberate: this POST registers a download, so it must not be replayed
  # automatically. `user_agent:` overrides Homebrew's default for the reason given at `USER_AGENT`.
  def mint_signed_url(download_id, registration:, timeout: nil)
    endpoint = format(RESOLVE_ENDPOINT, country:, id: download_id)
    body = request_body(registration:)

    result = curl_output(
      "--request", "POST",
      "--header", "Content-Type: application/json;charset=UTF-8",
      "--header", "Accept: application/json, text/plain, */*",
      "--header", "Origin: #{SITE}",
      "--header", "Referer: #{SITE}/#{country}/support/",
      "--data-raw", JSON.generate(body),
      endpoint,
      retries:    0,
      user_agent: USER_AGENT,
      timeout:
    )

    response = result.stdout.strip
    resolved = result.success? && response.start_with?("https://")

    unless resolved
      raise CurlDownloadStrategyError.new(endpoint, <<~MESSAGE)
        Blackmagic Design refused to issue a download URL. Their response was:
          #{response.presence || "(empty, curl exited #{result.status.exitstatus})"}
        #{registration_hint(response)}
        This request is not retried automatically.
      MESSAGE
    end

    response
  end

  # A refusal that mentions registration is about the identity fields, not about the download — either
  # the details in the config file are not ones Blackmagic accept, or upstream started requiring
  # registration for a release their catalog still flags as anonymous (in which case the flag, and so
  # the body, was read before this request — nothing to fix in the cask). Naming the file is the one
  # thing that turns Blackmagic's own wording into something actionable.
  def registration_hint(response)
    return "" unless response.match?(/regist/i)

    <<~HINT

      Blackmagic want registration details for this download. They come from
      #{BmdConfig.path}
      (or #{BmdConfig::ENV_PREFIX}* in the environment) — check that every field there is one they
      would accept, and that the email and phone are real.
    HINT
  end

  # The two bodies Blackmagic's own download modal posts, which are the two this sends.
  #
  # Common to both: `platform`, `policy`, `origin`, and `country` — mandatory even though the country
  # also appears in the path; omitting it is a 400.
  #
  # What actually discriminates them is `product`, not the identity fields and not `downloadOnly`:
  # their "Download only" button sets `downloadOnly` and sends no `product`, while their registration
  # form sends the product and no `downloadOnly` (`SupportModalDownloadStartCtrl` in
  # `support-bundle.js`). The endpoint reads it the same way — a registration-gated release answers
  # `403 Must register …` to a body with a full set of identity fields but no `product`, and issues a
  # signed URL for the same body with one. So `product` is what marks a request as a registration
  # rather than an anonymous download, and it must be non-empty.
  #
  # Nothing here asserts agreement to anything: `_fetch` refuses `requiresTermsAndConditions`
  # releases outright, and the endpoint wants no terms flag for the rest.
  def request_body(registration:)
    body = {
      "platform" => BmdCatalog::PLATFORM,
      "policy"   => true,
      "country"  => country,
      "origin"   => "www.blackmagicdesign.com",
    }
    return body.merge("downloadOnly" => true) unless registration

    body.merge("product" => @product, **BmdConfig.registration_details)
  end

  def country
    BmdCatalog.country
  end
end
