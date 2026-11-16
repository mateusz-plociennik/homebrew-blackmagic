cask "blackmagic-atem-switchers" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "11.0.1"
  sha256 "668acb328e52d6980cfc28335b0faee242ee38ee4dd5b68021dafe8ec8fda28f"

  url "https://sw.blackmagicdesign.com/ATEM/v#{version}/Blackmagic_ATEM_Switchers_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "ATEM Switchers" }
  name "ATEM Switchers"
  desc "Utility for setting up and updating ATEM Switchers"
  homepage "https://www.blackmagicdesign.com/support/family/atem-live-production-switchers"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("ATEM Switchers")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on :macos

  pkg "Install ATEM #{version}.pkg"

  uninstall pkgutil: [
    "^com\\.blackmagic-design\\.StreamingBridge$",
    "^com\\.blackmagic-design\\.Switchers$",
    "^com\\.blackmagic-design\\.SwitchersAssets$",
    "^com\\.blackmagic-design\\.SwitchersUninstaller$",
  ]
end
