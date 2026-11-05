cask "blackmagic-atem-switchers" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "11.0"
  sha256 "609f7da81e4c84ba3abeaaca22ff9b847aeb4e19b1fc92f0973bc68b27584e40"

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
