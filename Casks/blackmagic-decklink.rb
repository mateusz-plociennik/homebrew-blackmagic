cask "blackmagic-decklink" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "7.9.4"
  sha256 "281ee3ed0ef558f2bef58f2c513059730b329de7dba22d092ac6d8ed9bde70ff"

  url "https://sw.blackmagicdesign.com/DeckLink/v#{version}/DeckLink_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "DeckLink" }
  name "DeckLink"
  desc "Driver and utility software for Blackmagic DeckLink capture cards"
  homepage "https://www.blackmagicdesign.com/support/family/capture-and-playback"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("DeckLink")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  # The legacy vendor scripts remove shared drivers and utilities. Cintel ships overlapping
  # components, so keep it mutually exclusive and use the vendor's DeckLink-specific cleanup.
  conflicts_with cask: "blackmagic-cintel"
  depends_on :macos, arch: :x86_64
  # The package includes an unrelated Apple QuickTime component; do not install its system receipt.
  container nested: "DeckLink #{version}.dmg"

  pkg "DeckLink Installer #{version}.mpkg",
      choices: [
        {
          "choiceIdentifier" => "choice21",
          "choiceAttribute"  => "selected",
          "attributeSetting" => 0,
        },
      ]

  uninstall launchctl: "com.blackmagic-design.DeckLinkStartup",
            script:    {
              executable: "DeckLink Installer/Uninstall DeckLink.app/Contents/Resources/uninstall.sh",
              args:       ["DeckLink"],
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
    The download is anonymous, but the installer includes a separate DeckLink licence agreement.
    Review and accept applicable vendor terms yourself; this tap does not provide a software licence
    or bypass any activation requirement.

    The vendor installer and uninstaller remove shared Blackmagic components. This cask conflicts
    with Blackmagic Cintel; reinstall any affected Blackmagic products after uninstalling DeckLink.
  EOS
end
