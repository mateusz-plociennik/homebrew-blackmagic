cask "blackmagic-multiview" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "2.2.5"
  sha256 "c494900f70d50fb1d6a65df308226935f686ea6a2977c039d1266dfb0829ab53"

  url "https://sw.blackmagicdesign.com/MultiView/v#{version}/Blackmagic_MultiView_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Blackmagic MultiView" }
  name "Blackmagic MultiView"
  desc "Utility for updating Blackmagic MultiView hardware"
  homepage "https://www.blackmagicdesign.com/support/family/multiview-monitoring"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Blackmagic MultiView")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on :macos

  pkg "Install MultiView #{version}.pkg"

  uninstall script:  {
              executable: "Uninstall MultiView.app/Contents/Resources/uninstall.sh",
              sudo:       true,
            },
            pkgutil: [
              "^com\\.blackmagic-design\\.MultiView$",
              "^com\\.blackmagic-design\\.MultiViewAssets$",
              "^com\\.blackmagic-design\\.MultiViewUninstaller$",
            ]
end
