cask "blackmagic-ethernet-switch" do
  # Both details here are forced by how `brew bump-cask-pr` reloads a cask, and both look wrong until
  # you try the obvious form.
  #
  # *Inside* the block, because `Cask::CaskLoader::FromContentLoader.try_new` only accepts content
  # matching `/\A\s*cask ... end\s*\Z/` — a `require` above the block makes the file unloadable from
  # its own contents, and `bump-cask-pr` reloads it that way to compute the new `sha256`. It fails
  # with "No Cask with this name exists", quoting the whole file back as the name.
  #
  # `require` rather than `require_relative`, because that same loader `instance_eval`s the contents
  # with `Library/Homebrew` as the base, so a relative path resolves outside the tap and raises
  # LoadError. Asking the tap for its own path works under every loader.
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "1.2"
  sha256 "a34c37122939e82b60e08afd0d442fbc5d48bf034d107c36eec6663e3c3069fb"

  # Never fetched directly — this unsigned path 404s. BmdDownloadStrategy mints a signed URL at
  # fetch time; this stable string is what Homebrew keys its download cache on.
  #
  # `data:` carries the product's catalog name to the strategy, which pairs it with `version` to look
  # the download id up — so `version` is the only thing a bump has to touch. The release name is not
  # spelled out here because it is not derivable from the version: point releases are suffixed
  # ` Update`. `data:` is inert under CurlDownloadStrategy; never pair it with `using: :post`, which
  # would POST it to the artifact host.
  url "https://sw.blackmagicdesign.com/EthernetSwitch/v#{version}/Blackmagic_Ethernet_Switch_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Blackmagic Ethernet Switch" }
  name "Blackmagic Ethernet Switch"
  desc "Setup and monitoring utility for Blackmagic Ethernet Switch hardware"
  homepage "https://www.blackmagicdesign.com/products/blackmagicethernetswitch"

  # `release_regex` builds the both-ends-anchored pattern from the same product name the `data:` stanza
  # carries, so livecheck and the download-id lookup cannot disagree about which releases belong to
  # this cask. See `BmdCatalog` for why the catalog is read instead of the version-pointer endpoint,
  # why the anchoring matters, and which suffixes the pattern accepts.
  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Blackmagic Ethernet Switch")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  # The pkg's own installer check refuses anything below 10.14 (Mojave), but Homebrew dropped that
  # symbol — `:catalina` is the oldest version it can still express, and it no longer runs on 10.14.
  depends_on macos: :catalina

  # The .zip contains a .dmg containing the .pkg; Homebrew unpacks nested archives for us.
  pkg "Install Ethernet Switch #{version}.pkg"

  # Three receipts: EthernetSwitch, EthernetSwitchAssets, EthernetSwitchUninstaller. This value is a
  # regex passed to `pkgutil --pkgs=`, not a shell glob, so it needs `.*` rather than `*`.
  uninstall pkgutil: "com.blackmagic-design.EthernetSwitch.*"
end
