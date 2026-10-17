cask "blackmagic-camera-prodock" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "1.1.1"
  sha256 "8ea16d33f4f539c6ac22f5afa74e712b64796923713902fdb4f198d17dc68fa0"

  url "https://sw.blackmagicdesign.com/ProDock/v#{version}/Blackmagic_Camera_ProDock_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Blackmagic Camera ProDock" }
  name "Blackmagic Camera ProDock"
  desc "Utility for updating and managing Blackmagic Camera ProDock"
  homepage "https://www.blackmagicdesign.com/support/family/professional-cameras"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Blackmagic Camera ProDock")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on :macos

  pkg "Install Camera ProDock #{version}.pkg"

  uninstall script:  {
              executable: "Uninstall Camera ProDock.app/Contents/Resources/uninstall.sh",
              sudo:       true,
            },
            pkgutil: [
              "^com\\.blackmagic-design\\.StoneCutter$",
              "^com\\.blackmagic-design\\.StoneCutterAssets$",
              "^com\\.blackmagic-design\\.StoneCutterUninstaller$",
            ]
end
