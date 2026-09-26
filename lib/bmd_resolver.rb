# typed: false
# frozen_string_literal: true

require "json"
require "utils/curl"

require_relative "bmd_catalog"
require_relative "bmd_config"

# The resolve POST: the one request that turns a catalog `downloadId` into a CloudFront-signed URL.
#
# Both sides of the tap make it — `BmdDownloadStrategy` at install time and `BmdCaskGenerator` when
# scaffolding a cask — and they must make it identically, because every detail of it was established
# empirically against Blackmagic rather than read from a spec:
#
#   * an empty `User-Agent`: the endpoint answers `400 Bad Request` to any UA containing the
#     substring "curl", which Homebrew's default ends in. Only this endpoint filters; the artifact
#     host (`sw.blackmagicdesign.com`) does not.
#   * `retries: 0`: the POST *registers* a download, so a response that never arrives must not be
#     replayed. This is the tap's only unretryable request.
#   * `product` as the discriminator between the two bodies (see `request_body`).
#
# Sending the whole thing from one place is what keeps a fix to any of those from landing on the
# install path and not the scaffolding one, which nobody exercises day to day.
module BmdResolver
  ENDPOINT = "https://www.blackmagicdesign.com/api/register/%<country>s/download/%<id>s"
  SITE = "https://www.blackmagicdesign.com"
  USER_AGENT = ""

  # Blackmagic would not issue a URL. Carries the endpoint separately from the message so each caller
  # can raise its own error class around it — `CurlDownloadStrategyError` wants the URL as its first
  # argument, and the generator only wants the words.
  class RefusedError < RuntimeError
    attr_reader :endpoint

    def initialize(endpoint, message)
      @endpoint = endpoint
      super(message)
    end
  end

  class << self
    # Ask Blackmagic for a signed URL. Returns it as a bare string — the endpoint answers with the URL
    # as its plain-text body, not JSON — and raises `RefusedError` for anything else.
    def mint_signed_url(download_id, product: nil, registration: false, terms: false, timeout: nil)
      country = BmdCatalog.country
      endpoint = format(ENDPOINT, country:, id: download_id)

      result = Utils::Curl.curl_output(
        "--request", "POST",
        "--header", "Content-Type: application/json;charset=UTF-8",
        "--header", "Accept: application/json, text/plain, */*",
        "--header", "Origin: #{SITE}",
        "--header", "Referer: #{SITE}/#{country}/support/",
        "--data-raw", JSON.generate(request_body(product:, registration:, terms:)),
        endpoint,
        retries:    0,
        user_agent: USER_AGENT,
        timeout:
      )

      response = result.stdout.strip
      return response if result.success? && response.start_with?("https://")

      raise RefusedError.new(endpoint, <<~MESSAGE)
        Blackmagic Design refused to issue a download URL. Their response was:
          #{response.presence || "(empty, curl exited #{result.status.exitstatus})"}
        #{registration_hint(response)}
        This request is not retried automatically.
      MESSAGE
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
    # `hasAgreedToTerms` is sent only for a `requiresTermsAndConditions` release, and only once the
    # caller has established that the config file carries the opt-in — so the assertion Blackmagic
    # receive is one the user actually made, in writing, in a file they edited. Their own modal sends
    # the same field from the same checkbox (`supportFormDetails` in `support-bundle.js` seeds
    # `formData.hasAgreedToTerms = false` whenever the release has terms). Ungated releases send
    # nothing of the kind; the endpoint does not want it.
    def request_body(product: nil, registration: false, terms: false)
      body = {
        "platform" => BmdCatalog::PLATFORM,
        "policy"   => true,
        "country"  => BmdCatalog.country,
        "origin"   => "www.blackmagicdesign.com",
      }
      body["hasAgreedToTerms"] = true if terms
      return body.merge("downloadOnly" => true) unless registration

      body.merge("product" => product, **BmdConfig.registration_details)
    end

    # A refusal that mentions registration is about the identity fields, not about the download —
    # either the details in the config file are not ones Blackmagic accept, or upstream started
    # requiring registration for a release their catalog still flags as anonymous (in which case the
    # flag, and so the body, was read before this request — nothing to fix in the cask). Naming the
    # file is the one thing that turns Blackmagic's own wording into something actionable.
    def registration_hint(response)
      return "" unless response.match?(/regist/i)

      <<~HINT

        Blackmagic want registration details for this download. They come from
        #{BmdConfig.path}
        (or #{BmdConfig::ENV_PREFIX}* in the environment) — check that every field there is one they
        would accept, and that the email and phone are real.
      HINT
    end
  end
end
