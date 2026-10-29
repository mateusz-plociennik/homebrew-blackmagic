cask "blackmagic-multibridge" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "7.9.4"
  sha256 "87f1d59645c2654f520351ffdc8b670ab1aba918df3ac63a1417ceb1018f889c"

  url "https://sw.blackmagicdesign.com/Multibridge/v#{version}/Multibridge_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Multibridge" }
  name "Multibridge"
  desc "Driver and utility software for Blackmagic Multibridge capture hardware"
  homepage "https://www.blackmagicdesign.com/support/family/capture-and-playback"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Multibridge")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  conflicts_with cask: ["blackmagic-cintel", "blackmagic-decklink"]
  depends_on :macos, arch: :x86_64
  container nested: "Multibridge #{version}.dmg"

  # The enclosing MPKG sets customize="never", so installer choice changes leave no selected payload.
  # Install its seven Blackmagic packages directly, leaving its unrelated Apple codec untouched.
  pkg "Multibridge Installer #{version}.mpkg/Contents/Packages/blackmagicdecklinkapplications.pkg"
  pkg "Multibridge Installer #{version}.mpkg/Contents/Packages/blackmagicdecklinkcodec.pkg"
  pkg "Multibridge Installer #{version}.mpkg/Contents/Packages/blackmagicdecklinkdriver.pkg"
  pkg "Multibridge Installer #{version}.mpkg/Contents/Packages/blackmagicdecklinkpreferencepanes.pkg"
  pkg "Multibridge Installer #{version}.mpkg/Contents/Packages/blackmagicdecklinklaunchdaemons.pkg"
  pkg "Multibridge Installer #{version}.mpkg/Contents/Packages/blackmagicdecklinksupport.pkg"
  pkg "Multibridge Installer #{version}.mpkg/Contents/Packages/blackmagicdecklinkfinalcutprosupport.pkg"

  # The vendor uninstaller removes shared DeckLink drivers and tools, including Cintel's Disk Speed
  # Test app. Keep the receipts exact and block coexistence with products that use those components.
  uninstall launchctl: "com.blackmagic-design.DeckLinkStartup",
            script:    {
              executable: "Uninstall Multibridge.app/Contents/Resources/uninstall.sh",
              args:       ["Multibridge"],
              sudo:       true,
            },
            pkgutil:   [
              "^com\\.blackmagic-design\\.BlackmagicDeckLinkApplications$",
              "^com\\.blackmagic-design\\.BlackmagicDeckLinkCodec$",
              "^com\\.blackmagic-design\\.BlackmagicDeckLinkDriver$",
              "^com\\.blackmagic-design\\.BlackmagicDeckLinkFinalCutProSupport$",
              "^com\\.blackmagic-design\\.BlackmagicDecklinkLaunchDaemons$",
              "^com\\.blackmagic-design\\.BlackmagicDeckLinkPreferencePanes$",
              "^com\\.blackmagic-design\\.BlackmagicDeckLinkSupport$",
            ]

  caveats <<~EOS
    This release is for Intel Macs; its release notes list OS X 10.6.5 or later. The catalog currently
    allows anonymous downloads without a download-terms gate, but the installer includes a separate
    vendor licence agreement. Review and accept the applicable terms yourself; downloading does not
    provide a software licence or bypass activation requirements.

    The vendor uninstaller removes shared Blackmagic components. Multibridge conflicts with
    Blackmagic Cintel and DeckLink; reinstall any affected Blackmagic products after uninstalling it.
  EOS
end
