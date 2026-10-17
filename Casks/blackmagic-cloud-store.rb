cask "blackmagic-cloud-store" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "2.1"
  sha256 "d3e7b552b7b11e3b485d2fc5541787e9e395754eb104673ac933b71b4083f4ac"

  url "https://sw.blackmagicdesign.com/CloudStore/v#{version}/Blackmagic_Cloud_Store_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Blackmagic Cloud Store" }
  name "Blackmagic Cloud Store"
  desc "Utility for setting up Blackmagic Cloud Store network storage"
  homepage "https://www.blackmagicdesign.com/support/family/blackmagic-cloud-store"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Blackmagic Cloud Store")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on :macos

  pkg "Install Cloud Store #{version}.pkg"

  uninstall pkgutil: "(?:com\\.blackmagic\\-design\\.SharedStorage|com\\.blackmagic\\-design\\.ManifestProxyGenerator|com\\.blackmagic\\-design\\.SharedStorageAssets|com\\.blackmagic\\-design\\.SharedStorageUninstaller)"
end
