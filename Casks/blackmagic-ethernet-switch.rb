require_relative "../lib/bmd_download_strategy"

cask "blackmagic-ethernet-switch" do
  version "1.2"
  sha256 "a34c37122939e82b60e08afd0d442fbc5d48bf034d107c36eec6663e3c3069fb"

  # Never fetched directly — this unsigned path 404s. BmdDownloadStrategy mints a signed URL at
  # fetch time; this stable string is what Homebrew keys its download cache on.
  #
  # `data:` carries the download id to the strategy. It is inert under CurlDownloadStrategy; never
  # pair it with `using: :post`, which would POST it to the artifact host instead.
  url "https://sw.blackmagicdesign.com/EthernetSwitch/v#{version}/Blackmagic_Ethernet_Switch_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "downloadId" => "8d83aa9aa2684f1788d1b68da1c01ae7" }
  name "Blackmagic Ethernet Switch"
  desc "Setup and monitoring utility for Blackmagic Ethernet Switch hardware"
  homepage "https://www.blackmagicdesign.com/products/blackmagicethernetswitch"

  # The pkg's own installer check refuses anything below 10.14 (Mojave), but Homebrew dropped that
  # symbol — `:catalina` is the oldest version it can still express, and it no longer runs on 10.14.
  depends_on macos: :catalina

  # The .zip contains a .dmg containing the .pkg; Homebrew unpacks nested archives for us.
  pkg "Install Ethernet Switch #{version}.pkg"

  # Three receipts: EthernetSwitch, EthernetSwitchAssets, EthernetSwitchUninstaller. This value is a
  # regex passed to `pkgutil --pkgs=`, not a shell glob, so it needs `.*` rather than `*`.
  uninstall pkgutil: "com.blackmagic-design.EthernetSwitch.*"
end
