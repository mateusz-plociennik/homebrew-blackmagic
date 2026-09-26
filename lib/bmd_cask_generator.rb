# typed: false
# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"
require "macos_version"
require "utils/curl"

require_relative "bmd_catalog"
require_relative "bmd_resolver"
require_relative "bmd_terms"

# Scaffolds a cask from Blackmagic's catalog, readme and artifact. See #10.
#
# This is a bootstrapping tool, not infrastructure: it births a cask once, a human hand-finishes
# `desc` and install-verifies it, and it is never run against that cask again — casks are
# hand-maintained after birth. No cask ever loads this file; `BmdCatalog` stays read-only from this
# side, so nothing here writes to `lib/bmd_catalog.rb`.
#
# Run via `brew ruby bin/generate-cask "<Product Name>"`.
module BmdCaskGenerator
  TAP_NAME = "mateusz-plociennik/blackmagic"

  README_URL_TEMPLATE = "https://www.blackmagicdesign.com/support/content/readme/%<release_id>s"
  FAMILY_HOMEPAGE_TEMPLATE = "https://www.blackmagicdesign.com/support/family/%<slug>s"
  HTTP_STATUS_WRITE_OUT = format("%%%<token>s", token: "{http_code}").freeze

  # Per-product `desc`/`homepage`/`token` overrides, for the handful where the derived value is wrong
  # or a real product page exists. Keyed on the catalog product name.
  OVERRIDES = {
    "Blackmagic Ethernet Switch" => {
      homepage: "https://www.blackmagicdesign.com/products/blackmagicethernetswitch",
    },
  }.freeze

  # Every macOS release a cask can name, oldest first. Read from Homebrew rather than written out so
  # the floor moves when Homebrew drops a release: `Homebrew/OSDependsOn` fails a cask that names one
  # at or below the oldest supported, which is how a hand-written copy would go stale.
  MACOS_SYMBOLS = MacOSVersion::SYMBOLS.invert.sort_by { |version, _| version.split(".").map(&:to_i) }.to_h.freeze

  # The version in a pkg's own `pm_install_check()` OS test, whichever way round the comparison is
  # written. Both orders are in the wild — Ethernet Switch has
  # `compareVersions(system.version.ProductVersion, "10.15") < 0`, Resolve has
  # `compareVersions('15.0', system.version.ProductVersion) > 0` — and reading only the first silently
  # scaffolded a cask with no `depends_on macos:` at all.
  MIN_OS_PATTERNS = [
    /pm_install_check.*?compareVersions\(\s*system\.version\.ProductVersion\s*,\s*["']([\d.]+)["']\s*\)/m,
    /pm_install_check.*?compareVersions\(\s*["']([\d.]+)["']\s*,\s*system\.version\.ProductVersion\s*\)/m,
  ].freeze

  # Helper-app basenames that shadow the product rather than naming it — a `brew search` for
  # "Ethernet Switch Setup" or "Uninstall Ethernet Switch" is not a thing anyone does.
  HELPER_APP_NAME = /\A(un)?install\b/i

  class GeneratorError < RuntimeError; end

  class << self
    # ---------------------------------------------------------------------
    # Pure — no network, no shell, no filesystem. Covered by
    # test/bmd_cask_generator_test.rb.
    # ---------------------------------------------------------------------

    # `"Blackmagic Ethernet Switch"` -> `"blackmagic-ethernet-switch"`. The `blackmagic-` prefix is
    # applied universally (see #10), including to products whose catalog name doesn't carry it.
    def token_for(product_name)
      slug = product_name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      slug.start_with?("blackmagic-") ? slug : "blackmagic-#{slug}"
    end

    # A `desc` draft from the readme's intro paragraph. Never usable verbatim — Homebrew's `desc`
    # rules want a short phrase, no leading article, no product-name repetition — so this is a
    # starting point for a human to rewrite, not a final value. See `OVERRIDES` for the finished ones.
    def desc_draft_from_readme(html)
      # The intro lives in the first <p> after the "Welcome to ..." <h3>; every other <p> in the
      # fragment (what's new, licensing, disclaimer, date) is not a description.
      paragraph = html[%r{<h3>\s*Welcome to.*?</h3>\s*<p>(.*?)</p>}m, 1]
      return if paragraph.nil?

      paragraph.gsub(/<[^>]+>/, "").gsub(/\s+/, " ").strip
    end

    def homepage_for_family(slug)
      return if slug.blank?

      format(FAMILY_HOMEPAGE_TEMPLATE, slug:)
    end

    # The Homebrew `depends_on macos:` symbol for the version string a pkg's own installer check
    # names (e.g. `"10.14"`), rounded *up* to the nearest symbol Homebrew can express.
    #
    # `nil` when the pkg names nothing, and also when it names the oldest release Homebrew still
    # supports or older: every mac Homebrew will install on already clears that floor, so naming it is
    # redundant and `Homebrew/OSDependsOn` fails the cask for it. Both render as a bare
    # `depends_on :macos`.
    def macos_symbol_for(min_version)
      return if min_version.blank?

      # Trailing zeros dropped so "15.0" compares equal to "15", not above it.
      parts = ->(v) { v.split(".").map(&:to_i).reverse.drop_while(&:zero?).reverse }
      wanted = parts.call(min_version)
      version, symbol = MACOS_SYMBOLS.find { |candidate, _| (parts.call(candidate) <=> wanted) >= 0 }
      raise GeneratorError, "no macOS release Homebrew knows of covers #{min_version}" if symbol.nil?

      symbol if version != MACOS_SYMBOLS.keys.first
    end

    # The regex a cask's `uninstall pkgutil:` stanza passes to `pkgutil --pkgs=`: the longest common
    # prefix of every receipt identifier, plus `.*` — never a shell glob's bare `*`. A prefix ending
    # at a namespace separator or with a suspiciously short product segment is too broad to use, so
    # preserve the exact identifiers as an alternation instead.
    def pkgutil_regex_for(identifiers)
      raise ArgumentError, "no pkg identifiers given" if identifiers.empty?
      return identifiers.first if identifiers.size == 1

      prefix = identifiers.min.chars.zip(identifiers.max.chars)
                          .take_while { |a, b| a == b }
                          .map(&:first)
                          .join
      raise GeneratorError, "pkg receipts share no common prefix: #{identifiers.join(", ")}" if prefix.empty?

      product_prefix = prefix.split(".").last
      return "(?:#{identifiers.map { |identifier| Regexp.escape(identifier) }.join("|")})" if
        prefix.end_with?(".") || product_prefix.length < 4

      "#{prefix}.*"
    end

    # Rewrites the one exact occurrence of `version` in `template` (a filename or URL) into the
    # literal Ruby interpolation `#{version}`, so a bump only ever has to touch the `version` stanza.
    # Bounded so a version like `"1.2"` cannot swallow part of a longer number it happens to prefix.
    def versioned_template(template, version)
      pattern = /(?<![\d.])#{Regexp.escape(version)}(?!\.?\d)/
      raise GeneratorError, "#{version.inspect} does not appear in #{template.inspect}" unless template.match?(pattern)

      template.gsub(pattern, "\#{version}")
    end

    # App names worth adding as search aliases alongside the catalog product name — everything
    # except installer/uninstaller/setup helper apps, which don't help anyone find the product.
    def name_stanzas(product_name, app_names)
      extra = app_names.reject { |name| name.match?(HELPER_APP_NAME) || name.match?(/\bsetup\z/i) }
      ([product_name] + extra).uniq
    end

    def render_cask(token:, version:, sha256:, product:, url_template:, name_list:, desc:, homepage:,
                    macos_symbol:, pkg_filename:, pkgutil_regex:)
      name_line = if name_list.size == 1
        name_list.first.dump
      else
        name_list.map(&:dump).join(", ")
      end

      <<~CASK
        cask #{token.dump} do
          require Tap.fetch(#{TAP_NAME.dump}).path/"lib/bmd_catalog"
          require Tap.fetch(#{TAP_NAME.dump}).path/"lib/bmd_download_strategy"

          version #{version.dump}
          sha256 #{sha256.dump}

          url #{url_template.dump.gsub('\#{version}', '#{version}')},
              using: BmdDownloadStrategy,
              data:  { "product" => #{product.dump} }
          name #{name_line}
          desc #{desc.dump}
          homepage #{homepage.dump}

          livecheck do
            url BmdCatalog::CATALOG_URL
            regex BmdCatalog.release_regex(#{product.dump})
            strategy :json, &BmdCatalog::MAC_RELEASES
          end

          depends_on #{macos_symbol ? "macos: :#{macos_symbol}" : ":macos"}

          pkg #{pkg_filename.dump.gsub('\#{version}', '#{version}')}

          uninstall pkgutil: #{pkgutil_regex.dump}
        end
      CASK
    end

    # ---------------------------------------------------------------------
    # Impure — network, shell, filesystem. Exercised by running the generator, not by unit tests.
    # ---------------------------------------------------------------------

    # Scaffolds `Casks/<token>.rb` for `product_name` and returns the path written. Raises
    # `GeneratorError` — naming what it found — on anything it cannot handle rather than emitting a
    # guessed cask.
    def generate(product_name, version: nil, timeout: nil, casks_dir: nil)
      releases = BmdCatalog.send(:releases, timeout:)
      release = if version
        BmdCatalog.find_mac_release(releases, product_name, version)
      else
        latest_mac_release(releases, product_name)
      end

      # Same gate as `BmdDownloadStrategy#_fetch`, and for the same reason: scaffolding downloads the
      # artifact, so it needs the licence accepted first, and only the person running this can accept
      # it. The refusal shows the agreement rather than naming it — `BmdTerms.text` raises if it
      # cannot read it, which stops the scaffold either way.
      terms = BmdCatalog.requires_terms?(release)
      if terms && !BmdConfig.accepts_terms?
        raise GeneratorError, <<~MESSAGE
          "#{release["name"]}" requires accepting Blackmagic Design's licence agreement.

          #{BmdTerms.text(release["termsAndConditions"], timeout:)}

          (#{BmdTerms.url(release["termsAndConditions"])})

          If you agree to it, record that in #{BmdConfig.path}:

          { "agreeToTerms": true }

          Nothing has been downloaded.
        MESSAGE
      end

      token = OVERRIDES.dig(product_name, :token) || token_for(product_name)
      casks_dir ||= File.expand_path("../Casks", __dir__)
      path = File.join(casks_dir, "#{token}.rb")
      if File.exist?(path)
        raise GeneratorError,
              "#{path} already exists — casks are hand-maintained after birth, not regenerated."
      end

      version_string = release["name"][BmdCatalog.release_regex(product_name), 1]
      download_id = release.dig("urls", BmdCatalog::PLATFORM, 0, "downloadId")
      unless download_id.present?
        raise GeneratorError,
              <<~MESSAGE
                Blackmagic's catalog lists "#{release["name"]}" but its Mac OS X build has no downloadId.
              MESSAGE
      end
      release_id = release.fetch("id")

      readme_html = fetch_readme(release_id, timeout:)
      desc = OVERRIDES.dig(product_name, :desc) || desc_draft_from_readme(readme_html) ||
             raise(GeneratorError,
                   "could not draft a desc from the readme at #{format(README_URL_TEMPLATE, release_id:)}")

      homepage = OVERRIDES.dig(product_name, :homepage) || homepage_for_family(release["relatedFamilies"]&.first) ||
                 raise(GeneratorError, "#{release["name"]} has no relatedFamilies to derive a homepage from")
      raise GeneratorError, "homepage #{homepage} did not answer HTTP 200" unless homepage_ok?(homepage, timeout:)

      signed_url = mint_signed_url(download_id, product: product_name,
                                   registration: BmdCatalog.requires_registration?(release),
                                   terms:, timeout:)

      Dir.mktmpdir("bmd-generate-cask") do |dir|
        zip_path = File.join(dir, "artifact.zip")
        download(signed_url, zip_path, timeout:)
        sha256 = Digest::SHA256.file(zip_path).hexdigest
        artifact = introspect_artifact(zip_path, dir)

        url_template = versioned_template(unsigned_path(signed_url), version_string)
        pkg_filename = versioned_template(artifact.fetch(:pkg_filename), version_string)
        pkgutil_regex = pkgutil_regex_for(artifact.fetch(:identifiers))
        macos_symbol = macos_symbol_for(artifact[:min_os_version])
        name_list = name_stanzas(product_name, artifact.fetch(:app_names))

        cask = render_cask(
          token:, version: version_string, sha256:, product: product_name, url_template:,
          name_list:, desc:, homepage:, macos_symbol:, pkg_filename:, pkgutil_regex:
        )
        FileUtils.mkdir_p(casks_dir)
        File.write(path, cask)
      end

      path
    end

    # The mac-shipping release of `product` with the highest version, across the whole catalog —
    # what a first-time generate should scaffold, absent an explicit `version:`.
    def latest_mac_release(releases, product)
      pattern = BmdCatalog.release_regex(product)
      candidates = releases.select do |entry|
        entry["name"].to_s.match?(pattern) && entry.dig("urls", BmdCatalog::PLATFORM).present?
      end
      raise GeneratorError, "Blackmagic's catalog has no macOS release for \"#{product}\"." if candidates.empty?

      downloadable = candidates.select do |entry|
        entry.dig("urls", BmdCatalog::PLATFORM, 0, "downloadId").present?
      end
      return downloadable.max_by { |entry| entry["name"][pattern, 1].split(".").map(&:to_i) } if downloadable.any?

      release = candidates.max_by { |entry| entry["name"][pattern, 1].split(".").map(&:to_i) }

      raise GeneratorError,
            <<~MESSAGE
              Blackmagic's catalog lists "#{release["name"]}" but its Mac OS X build has no downloadId.
            MESSAGE
    end

    def fetch_readme(release_id, timeout: nil)
      url = format(README_URL_TEMPLATE, release_id:)
      result = Utils::Curl.curl_output(url, timeout:)
      unless result.success?
        raise GeneratorError,
              "could not fetch readme at #{url} (curl exited #{result.status.exitstatus})"
      end

      result.stdout
    end

    def homepage_ok?(url, timeout: nil)
      result = Utils::Curl.curl_output("--silent", "--output", File::NULL, "--write-out", HTTP_STATUS_WRITE_OUT, url,
                                       timeout:)
      result.success? && result.stdout.strip == "200"
    end

    # Mints a signed download URL through `BmdResolver`, the same code the install path runs — with the
    # registration fields when the release needs them, since scaffolding a registration-path cask means
    # actually downloading its artifact, and `hasAgreedToTerms` for a gated release, which `generate`
    # only reaches once the config file carries the opt-in.
    def mint_signed_url(download_id, product: nil, registration: false, terms: false, timeout: nil)
      BmdResolver.mint_signed_url(download_id, product:, registration:, terms:, timeout:)
    rescue BmdResolver::RefusedError => e
      raise GeneratorError, e.message
    end

    def unsigned_path(signed_url)
      signed_url.split("?", 2).first
    end

    def download(url, dest, timeout: nil)
      result = Utils::Curl.curl_output("--location", "--output", dest, url, timeout:)
      return if result.success? && File.exist?(dest)

      raise GeneratorError,
            "download failed (curl exited #{result.status.exitstatus})"
    end

    # Unzip -> hdiutil attach -> pkgutil --expand, read-only and sudo-free throughout. Returns the
    # `pkg` stanza filename, the receipt identifiers, the installer's own minimum OS version (if any)
    # and any non-helper app names found in the payload, via `lsbom` — never extracted.
    #
    # Hard-fails, naming what it found, on any shape other than pkg-in-dmg-in-zip: that is the only
    # shape observed so far (#10), and a guessed install stanza fails on someone else's machine.
    def introspect_artifact(zip_path, work_dir)
      unzip_dir = File.join(work_dir, "unzipped")
      FileUtils.mkdir_p(unzip_dir)
      system("unzip", "-q", "-o", zip_path, "-d", unzip_dir, exception: true)

      dmgs = Dir.glob(File.join(unzip_dir, "*.dmg"))
      other = Dir.entries(unzip_dir) - %w[. ..] - dmgs.map { |d| File.basename(d) }
      if dmgs.size != 1
        found = dmgs.map { |d| File.basename(d) } + other
        raise GeneratorError,
              "unrecognised artifact shape: expected exactly one .dmg in the zip, found #{found.inspect}"
      end

      mountpoint = File.join(work_dir, "mnt")
      attach = system("hdiutil", "attach", "-nobrowse", "-readonly", "-mountpoint", mountpoint, dmgs.first,
                      exception: true)
      raise GeneratorError, "hdiutil attach failed for #{dmgs.first}" unless attach

      begin
        pkgs = Dir.glob(File.join(mountpoint, "*.pkg"))
        apps_at_root = Dir.glob(File.join(mountpoint, "*.app"))
        if pkgs.size != 1
          shape = if apps_at_root.any?
            "a plain dmg with an app (#{apps_at_root.map do |a|
              File.basename(a)
            end.join(", ")})"
          else
            "#{pkgs.size} pkgs"
          end
          raise GeneratorError, "unrecognised artifact shape: #{shape} in #{File.basename(dmgs.first)}"
        end

        introspect_pkg(pkgs.first, work_dir)
      ensure
        system("hdiutil", "detach", "-quiet", mountpoint)
      end
    end

    def introspect_pkg(pkg_path, work_dir)
      expand_dir = File.join(work_dir, "expand")
      system("pkgutil", "--expand", pkg_path, expand_dir, exception: true)

      distribution = File.join(expand_dir, "Distribution")
      component_dirs = Dir.glob(File.join(expand_dir, "*.pkg"))

      identifiers, min_os_version =
        if File.exist?(distribution)
          parse_distribution(File.read(distribution))
        elsif component_dirs.empty?
          parse_single_component(expand_dir)
        else
          raise GeneratorError,
                "#{File.basename(pkg_path)} has component pkgs but no Distribution file — unrecognised artifact shape"
        end

      if identifiers.empty?
        raise GeneratorError,
              "could not find any pkg receipt identifiers in #{File.basename(pkg_path)}"
      end

      bom_paths = if component_dirs.any?
        component_dirs.map do |d|
          File.join(d, "Bom")
        end
      else
        [File.join(expand_dir, "Bom")]
      end
      app_names = bom_paths.flat_map { |bom| app_names_from_bom(bom) }.uniq

      { pkg_filename: File.basename(pkg_path), identifiers:, min_os_version:, app_names: }
    end

    # A product distribution's own installer check — `pm_install_check()`'s `compareVersions` call
    # against `system.version.ProductVersion` — not the volume check, which tests the *target disk*
    # rather than the machine running the installer.
    #
    # `MIN_OS_PATTERNS` covers both argument orders.
    def parse_distribution(xml)
      identifiers = xml.scan(/<pkg-ref id="([^"]+)"[^>]*installKBytes="[^"]*"[^>]*>/).flatten
      min_os_version = MIN_OS_PATTERNS.filter_map { |pattern| xml[pattern, 1] }.first
      [identifiers, min_os_version]
    end

    # A pkg with no Distribution is a single component: its own `PackageInfo` carries the identifier,
    # and there is no installer-script OS check to read.
    def parse_single_component(expand_dir)
      package_info = File.join(expand_dir, "PackageInfo")
      unless File.exist?(package_info)
        raise GeneratorError,
              "no Distribution or PackageInfo found — unrecognised artifact shape"
      end

      identifier = File.read(package_info)[/identifier="([^"]+)"/, 1]
      [[identifier].compact, nil]
    end

    def app_names_from_bom(bom_path)
      return [] unless File.exist?(bom_path)

      result = system_capture("lsbom", "-s", bom_path)
      result.lines.grep(/\.app\z/).map { |line| File.basename(line.strip, ".app") }
    end

    def system_capture(*command)
      require "open3"
      stdout, = Open3.capture2(*command)
      stdout
    end
  end
end
