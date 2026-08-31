# typed: false
# frozen_string_literal: true

# Homebrew's own download strategies are `# typed: strict`, but they live inside the Homebrew
# checkout that `srb` typechecks. Nothing typechecks `Library/Taps`, so a stricter sigil here would
# claim a guarantee no tool verifies, while a wrong `sig` still fails at runtime — inside
# `brew install`. The `sig` below is kept because sorbet-runtime does enforce it on every call.

require "download_strategy"
require "json"

require_relative "bmd_catalog"

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
# The release name travels in the cask's `data:` stanza. Only `CurlPostDownloadStrategy` ever reads
# `meta[:data]` (to build POST parameters); under `CurlDownloadStrategy` the key is inert, so it is
# free to carry our own metadata. Do not combine a `data:` stanza with `using: :post` in this tap.
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
    @release = meta.dig(:data, "release")
    return if @release.present?

    raise ArgumentError, "#{self.class.name} requires a `data: { \"release\" => \"...\" }` stanza"
  end

  private

  # Skip Homebrew's pre-flight HEAD request. It would probe the unsigned URL, which 404s by design.
  # Reporting the unsigned URL as its own resolution keeps both the cache key and the basename
  # derived from the stable path; `_fetch` ignores `resolved_url` and downloads a freshly signed one.
  # The trailing `nil`s are last-modified and content-length, which Homebrew only uses for cache
  # freshness heuristics — the pinned `sha256` is the real integrity check.
  #
  # This is also why `brew audit --cask --online` cannot pass for casks using this strategy: there is
  # no URL for it to validate. Do not "fix" this override to restore the probe.
  def resolve_url_basename_time_file_size(url, timeout: nil)
    [url, parse_basename(url), nil, nil, nil, false]
  end

  def _fetch(url:, resolved_url:, timeout:)
    download_id = BmdCatalog.mac_download_id(@release, timeout:)
    signed_url = mint_signed_url(download_id, timeout:)
    ohai "Minted a signed URL from #{SITE}" unless quiet?
    _curl_download signed_url, temporary_path, timeout
  end

  # Ask Blackmagic for a signed URL. Returns it as a bare string — the endpoint answers with the URL
  # as its plain-text body, not JSON.
  #
  # `retries: 0` is deliberate: this POST registers a download, so it must not be replayed
  # automatically. `user_agent:` overrides Homebrew's default for the reason given at `USER_AGENT`.
  def mint_signed_url(download_id, timeout: nil)
    endpoint = format(RESOLVE_ENDPOINT, country:, id: download_id)

    result = curl_output(
      "--request", "POST",
      "--header", "Content-Type: application/json;charset=UTF-8",
      "--header", "Accept: application/json, text/plain, */*",
      "--header", "Origin: #{SITE}",
      "--header", "Referer: #{SITE}/#{country}/support/",
      "--data-raw", JSON.generate(request_body),
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

        This request is not retried automatically.
      MESSAGE
    end

    response
  end

  # Fields Blackmagic require even for downloads that need no registration. `downloadOnly` is what
  # their own "Download only" button sets, and `country` is mandatory — omitting it is a 400.
  def request_body
    {
      "platform"     => "Mac OS X",
      "policy"       => true,
      "downloadOnly" => true,
      "country"      => country,
      "origin"       => "www.blackmagicdesign.com",
    }
  end

  def country
    BmdCatalog.country
  end
end
