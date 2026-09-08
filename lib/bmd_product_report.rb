# typed: false
# frozen_string_literal: true

require "json"
# The tap test runner preloads Set, but this module also runs as a standalone Ruby script.
# rubocop:disable Lint/RedundantRequireStatement
require "set" unless defined?(Set)
# rubocop:enable Lint/RedundantRequireStatement

require_relative "bmd_catalog"
require_relative "bmd_skip_list"

# Reports Blackmagic products that have neither a cask nor a recorded reason to stay uncasked. See
# #11. Cheap and scheduled, not continuous: files at most one issue per run, and never re-files while
# an open issue already reports the same set. Reuses `BmdCatalog`'s catalog read (#10's second entry
# point on the same script); `lib/bmd_catalog.rb` is unchanged by this.
module BmdProductReport
  ISSUE_TITLE = "New Blackmagic products with no cask"

  class << self
    # ---------------------------------------------------------------------
    # Pure — grouping and diffing logic. Covered by test/bmd_product_report_test.rb.
    # ---------------------------------------------------------------------

    # Every mac-shipping release, grouped into products: those matching `BmdSkipList::SKIP_REGEXES`
    # are dropped release-by-release *before* grouping (so a beta build's trailing digits never leak
    # into a base product name), everything else groups under its name with the trailing
    # `<version>(?: Update)?` stripped. Each product carries its release count and its latest release
    # (by `numericDate`) — what a human needs to triage, per #11.
    def products(releases)
      grouped = Hash.new { |h, k| h[k] = [] }

      releases.each do |release|
        name = release["name"].to_s
        next if release.dig("urls", BmdCatalog::PLATFORM).blank?
        next if BmdSkipList::SKIP_REGEXES.any? { |regex| name.match?(regex) }

        base = name[/\A(.+) #{BmdCatalog::VERSION_PATTERN}#{BmdCatalog::OPTIONAL_SUFFIX}\z/o, 1]
        next if base.nil?

        grouped[base] << release
      end

      grouped.transform_values { |group| { count: group.size, latest: group.max_by { |r| r["numericDate"].to_i } } }
    end

    # Products with neither a cask (`existing_products`, the catalog product names `Casks/*.rb`
    # already carry in their `data:` stanza) nor a skip-list entry.
    def missing(releases, existing_products)
      products(releases).reject do |name, _info|
        existing_products.include?(name) || BmdSkipList::SKIP_PRODUCTS.key?(name)
      end
    end

    # Skip-list entries whose reason names an issue number that is no longer open — worth a mention
    # since the entry may now be stale, but never blocks the run.
    def stale_skip_entries(open_issue_numbers)
      BmdSkipList::SKIP_PRODUCTS.filter_map do |name, reason|
        numbers = reason.scan(/#(\d+)/).flatten.map(&:to_i)
        next if numbers.empty? || numbers.any? { |n| open_issue_numbers.include?(n) }

        noun = (numbers.size == 1) ? "an issue" : "issues"
        verb = (numbers.size == 1) ? "is" : "are"
        "#{name}: \"#{reason}\" names #{noun} that #{verb} no longer open"
      end
    end

    # The catalog product names already carried by a cask's `data: { "product" => "..." }` stanza.
    def existing_products(casks_dir)
      Dir.glob(File.join(casks_dir, "*.rb")).flat_map do |path|
        File.read(path).scan(/"product"\s*=>\s*"([^"]+)"/).flatten
      end.to_set
    end

    def render_issue_body(missing, stale_entries)
      rows = missing.sort.map do |name, info|
        release = info[:latest]
        "| #{name} | #{info[:count]} | #{release["name"]} | #{release["date"]} | " \
          "#{release["requiresRegistration"]} | #{release["requiresTermsAndConditions"]} | " \
          "#{release["relatedFamilies"]&.first} |"
      end

      body = <<~BODY
        Products in Blackmagic's catalog with neither a cask nor a `lib/bmd_skip_list.rb` entry.

        | Product | Releases | Latest release | Date | Registration | Terms | Family |
        |---|---|---|---|---|---|---|
        #{rows.join("\n")}

        Bootstrap with `brew ruby bin/generate-cask "<Product Name>"` (#10) and install-verify (#12).
      BODY

      unless stale_entries.empty?
        body << "\n## Possibly-stale skip-list entries\n\n"
        stale_entries.each { |entry| body << "- #{entry}\n" }
      end

      body
    end

    # ---------------------------------------------------------------------
    # Impure — network (catalog + GitHub CLI) and filesystem.
    # ---------------------------------------------------------------------

    def run(casks_dir: nil, timeout: nil)
      casks_dir ||= File.expand_path("../Casks", __dir__)
      releases = BmdCatalog.send(:releases, timeout:)
      missing_products = missing(releases, existing_products(casks_dir))
      stale = stale_skip_entries(open_issue_numbers)
      stale.each { |entry| puts "stale skip-list entry: #{entry}" }

      if missing_products.empty?
        puts "No products found with neither a cask nor a skip-list entry."
      else
        report(missing_products, stale)
      end
    end

    private

    def report(missing_products, stale)
      if (existing = find_open_issue(missing_products.keys))
        puts <<~MESSAGE
          #{missing_products.size} product(s) missing a cask, but ##{existing} already reports this set.
          Not re-filing.
        MESSAGE
        return
      end

      body = render_issue_body(missing_products, stale)
      IO.popen(["gh", "issue", "create", "--title", ISSUE_TITLE, "--body-file", "-"], "w") { |io| io.write(body) }
    end

    def find_open_issue(missing_names)
      out = `gh issue list --state open --search #{ISSUE_TITLE.inspect} --json number,title,body 2>/dev/null`
      expected = missing_names.sort
      JSON.parse(out).find do |issue|
        issue["title"] == ISSUE_TITLE && issue_products(issue["body"]) == expected
      end&.fetch("number")
    rescue JSON::ParserError
      nil
    end

    def issue_products(body)
      body.to_s.lines.filter_map do |line|
        match = line.match(/\A\|\s+(.+?)\s+\|\s+\d+\s+\|/)
        match[1] if match
      end.sort
    end

    def open_issue_numbers
      out = `gh issue list --state open --limit 200 --json number 2>/dev/null`
      JSON.parse(out).map { |issue| issue["number"] }
    rescue JSON::ParserError
      []
    end
  end
end
