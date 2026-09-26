cask "blackmagic-atem-switchers" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "10.4.1"
  sha256 "2d18ea6d1c1553d9eb1a2cd568c4ed08df2d41d11c62ab96635448d7917dc751"

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

  uninstall pkgutil: "(?:com\\.blackmagic\\-design\\.Switchers|com\\.blackmagic\\-design\\.StreamingBridge|com\\.blackmagic\\-design\\.SwitchersAssets|com\\.blackmagic\\-design\\.SwitchersUninstaller)"
end
