# typed: false
# frozen_string_literal: true

# What #11 considers intentionally absent from `Casks/` — so a catalog-vs-`Casks/*.rb` diff doesn't
# re-report the same ~40 non-candidates (SDKs, betas, dead hardware, renames, registration-gated
# products) forever. Two mechanisms, per #11:
#
# - `SKIP_REGEXES` catches whole *categories* of release name by pattern.
# - `SKIP_PRODUCTS` is one line per *product*, because a regex can say "not an SDK" but not "Resolve
#   is waiting on #3" — and the day #3 lands, nothing else here tells you Resolve is now eligible.
#
# Committed and hand-maintained, not generated: reasons belong in the file, not in git history.
module BmdSkipList
  # Two lines that keep ~190 SDK and beta releases out of the grouping entirely, before a base
  # product name is ever extracted from them.
  SKIP_REGEXES = [
    / SDK\z/,
    / (Public )?Beta ?\d*\z/,
  ].freeze

  # Keyed on the catalog product name `BmdProductReport` groups releases under. Each value names the
  # reason, and an issue number where one exists, so a closed issue shows up as stale (see #11).
  SKIP_PRODUCTS = {
    # Terms-and-conditions gated: the tap has no way to show a licence before accepting it on
    # someone's behalf (#6), so it refuses these outright rather than agreeing for them.
    "Blackmagic RAW"                     => "registration + T&C — blocked on #6",
    "Blackmagic Fairlight Sound Library" => "registration + T&C — blocked on #6",

    # Registration-gated but no longer blocked: the config loader landed with
    # `blackmagic-davinci-resolve`, which is the cask that proved that path. These three are eligible
    # now, and each needs the same bootstrap-and-install-verify pass the anonymous products got. The
    # reasons name no issue on purpose — an entry naming a closed issue reports itself as stale, and
    # what is pending here is the install verification, not a ticket.
    "DaVinci Resolve Project Server"     => "registration path works; not yet install-verified",
    "Fairlight Live"                     => "registration path works; not yet install-verified",
    "Fusion Connect"                     => "registration path works; not yet install-verified",

    # A developer SDK, not an end-user app — the same reason `SKIP_REGEXES` excludes
    # "<product> <version> SDK" releases, but this product's own name carries "SDK", so its releases
    # are named "Blackmagic RAW SDK <version>" and never match that pattern.
    "Blackmagic RAW SDK"                 => "developer SDK, not an end-user app",

    # Dead hardware; latest release 2011-2019.
    "Blackmagic eGPU"                    => "dead hardware, last shipped 2011-2019",
    "Blackmagic RAW Player"              => "dead hardware, last shipped 2011-2019",
    "Blackmagic RAW Speed Test"          => "dead hardware, last shipped 2011-2019",
    "Blackmagic Duplicator"              => "dead hardware, last shipped 2011-2019",
    "Fusion"                             => "superseded by Fusion Studio",
    "Control for Arduino"                => "dead hardware, last shipped 2011-2019",
    "UltraScope"                         => "dead hardware, last shipped 2011-2019",
    "DaVinci Resolve Lite"               => "dead hardware, last shipped 2011-2019",
    "DeckLink"                           => "dead hardware, last shipped 2011-2019",
    "Multibridge"                        => "dead hardware, last shipped 2011-2019",

    # Superseded names — same product shipping today under a newer name.
    "Videohub"                           => "superseded rename — see Blackmagic Videohub",
    "MultiView"                          => "superseded rename — see Blackmagic MultiView",
    "Audio Monitor"                      => "superseded rename — see Blackmagic Audio Monitor",
    "HDLink"                             => "superseded rename — see HyperDeck",

    # Tracked in #12's bootstrap checklist; each gets a cask (and drops out of this list) as that
    # issue is worked through. Not yet on the checklist itself: `Ultimatte 12` is a distinct hardware
    # line from plain `Ultimatte` sharing the same qualification, so it is deferred the same way.
    "Blackmagic Video Assist"            => "tracked in #12",
    "Desktop Video"                      => "tracked in #12",
    "ATEM Switchers"                     => "tracked in #12",
    "Blackmagic Camera"                  => "tracked in #12",
    "Blackmagic Converters"              => "tracked in #12",
    "Blackmagic Camera ProDock"          => "tracked in #12",
    "Blackmagic Streaming"               => "tracked in #12",
    "Blackmagic Cloud Store"             => "tracked in #12",
    "Blackmagic Videohub"                => "tracked in #12",
    "Ultimatte"                          => "tracked in #12",
    "Ultimatte 12"                       => "tracked in #12",
    "HyperDeck"                          => "tracked in #12",
    "SmartView"                          => "tracked in #12",
    "Blackmagic Audio Monitor"           => "tracked in #12",
    "Blackmagic Cintel"                  => "tracked in #12",
    "Blackmagic Web Presenter"           => "tracked in #12",
    "Teranex"                            => "tracked in #12",
    "Blackmagic MultiView"               => "tracked in #12",
    "Fusion Studio"                      => "tracked in #12",
    "DaVinci Resolve Studio"             => "tracked in #12",
  }.freeze
end
