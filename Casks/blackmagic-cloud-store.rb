cask "blackmagic-cloud-store" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "2.0"
  sha256 "352f7621f5641eb5e800d263dc0f39c3d84d2741b13bd1426bc15e5c935c3554"

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

  uninstall pkgutil: "(?:com\\.blackmagic\\-design\\.SharedStorage|com\\.blackmagic\\-design\\.blackmagic\\-proxy\\-generator\\-lite\\-macos|com\\.blackmagic\\-design\\.SharedStorageAssets|com\\.blackmagic\\-design\\.SharedStorageUninstaller)"
end
