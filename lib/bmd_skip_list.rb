# typed: false
# frozen_string_literal: true

# Release names and catalog products that should never become casks in this tap.
# Product coverage backlog lives in #43; do not add pending/backlog products here.
module BmdSkipList
  # Two lines that keep ~190 SDK and beta releases out of the grouping entirely, before a base
  # product name is ever extracted from them.
  SKIP_REGEXES = [
    / SDK\z/,
    / (Public )?Beta ?\d*\z/,
  ].freeze

  # Keyed on the catalog product name `BmdProductReport` groups releases under.
  SKIP_PRODUCTS = {
    "Blackmagic RAW SDK" => "developer SDK, not an end-user app",
    "Fusion"             => "superseded by Fusion Studio",
    "Videohub"           => "superseded rename — see Blackmagic Videohub",
    "MultiView"          => "superseded rename — see Blackmagic MultiView",
    "Audio Monitor"      => "superseded rename — see Blackmagic Audio Monitor",
    "HDLink"             => "superseded rename — see HyperDeck",
  }.freeze
end
