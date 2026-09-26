# typed: false
# frozen_string_literal: true

require "cgi"
require "utils/curl"

# The licence agreements behind Blackmagic's `requiresTermsAndConditions` releases.
#
# The catalog does not carry the agreement, only a slug naming it: `"termsAndConditions" =>
# "bmd-braw-sdk-2"`. Six slugs cover all 224 gated releases, so these are a handful of shared licence
# documents rather than per-release text.
#
# The slug resolves through the same modal Blackmagic's own download button opens — their
# `support-bundle.js` builds `/support/modal/download-with-terms-start/<slug>` and renders it as step
# 2 of the download form. There is no JSON endpoint: every `/api/…/terms…` shape returns 404. So this
# reads that fragment, which is the document a person clicking "Agree" on the website is shown.
#
# It is an Angular template, and the agreement sits in a single `<div class="tandc">` alongside the
# registration form. Everything outside that div is form chrome; everything inside it is the licence.
module BmdTerms
  URL_TEMPLATE = "https://www.blackmagicdesign.com/support/modal/download-with-terms-start/%<slug>s"

  # The element holding the agreement, and nothing else.
  CONTAINER = '<div class="tandc">'

  class << self
    def url(slug)
      format(URL_TEMPLATE, slug:)
    end

    # The agreement as plain text. Raises rather than returning a placeholder: the only caller refuses
    # an install *because* it must show this, so text it could not read is not something to paper over
    # with a URL the user would have to go and read in a browser instead.
    def text(slug, timeout: nil)
      extract(fetch(slug, timeout:), slug)
    end

    # Tag-stripping rather than HTML parsing: Homebrew's Ruby ships no parser this tap can rely on,
    # and the target is one div of static prose. Split out from `fetch` so it is testable without the
    # network — see `test/bmd_terms_test.rb`.
    def extract(html, slug = nil)
      container = balanced_container(html)
      raise TermsError, missing_message(slug) if container.nil?

      # An empty div is the same failure as a missing one, and worse if allowed through: the refusal
      # would print nothing and still ask for agreement to it. Blank means unread, not "no terms".
      text = to_text(container).presence
      raise TermsError, missing_message(slug) if text.nil?

      text
    end

    private

    def fetch(slug, timeout: nil)
      result = Utils::Curl.curl_output("--compressed", url(slug), timeout:)

      raise TermsError, <<~MESSAGE unless result.success?
        Could not read Blackmagic's licence agreement at #{url(slug)}
        (curl exited #{result.status.exitstatus}).

        Nothing has been downloaded: this release requires agreeing to that licence, and the tap will
        not ask you to agree to a document it could not show you.
      MESSAGE

      result.stdout
    end

    # `CONTAINER` to its matching `</div>`, counting nested opens — the agreement contains none today,
    # but stopping at the first `</div>` would truncate silently the day it does.
    def balanced_container(html)
      start = html.index(CONTAINER)
      return if start.nil?

      depth = 0
      html[start..].to_enum(:scan, %r{<div\b|</div>}).each do
        depth += Regexp.last_match(0).start_with?("</") ? -1 : 1
        return html[start, Regexp.last_match.end(0)] if depth.zero?
      end

      nil
    end

    def to_text(html)
      html
        .gsub(%r{<br\s*/?>|</p>|</h\d>|</li>}i, "\n")
        .gsub(/<[^>]*>/, "")
        # `CGI.unescapeHTML` knows only the five XML entities, and `&nbsp;` is common in this prose —
        # left alone it prints literally, and a container holding nothing else would read as non-blank.
        .gsub(/&nbsp;/i, " ")
        .then { |text| CGI.unescapeHTML(text) }
        .gsub(/[ \t]+/, " ")
        .gsub(/ ?\n ?/, "\n")
        .gsub(/\n{3,}/, "\n\n")
        .strip
    end

    def missing_message(slug)
      <<~MESSAGE
        Blackmagic's licence agreement at #{url(slug)} no longer contains a
        `#{CONTAINER}` element with text in it, so the agreement could not be read from it.

        Nothing has been downloaded. Read the agreement in a browser at the URL above; the tap needs
        `lib/bmd_terms.rb` updated before it can show it to you itself.
      MESSAGE
    end
  end

  # Raised for every way the agreement can fail to be read. Subclasses `RuntimeError` so it surfaces
  # as a plain `Error:` line under `brew install` and exits non-zero, like `BmdCatalog::CatalogError`.
  class TermsError < RuntimeError; end
end
