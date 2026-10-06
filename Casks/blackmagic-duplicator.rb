cask "blackmagic-duplicator" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "1.2"
  sha256 "8e0d059cb933e300ef9d3c77c38d1a167257640b9fa28f3d5d509107fe5e351c"

  url "https://sw.blackmagicdesign.com/Duplicator/v#{version}/Blackmagic_Duplicator_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Blackmagic Duplicator" }
  name "Blackmagic Duplicator"
  desc "Utility for updating Blackmagic Duplicator 4K hardware"
  homepage "https://www.blackmagicdesign.com/support/family/disk-recorders"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Blackmagic Duplicator")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on :macos

  pkg "Install Duplicator v#{version}.pkg"

  uninstall script:  {
              executable: "Uninstall Duplicator.app/Contents/Resources/uninstall.sh",
              sudo:       true,
            },
            pkgutil: [
              "^com\\.blackmagic-design\\.Duplicator$",
              "^com\\.blackmagic-design\\.DuplicatorAssets$",
              "^com\\.blackmagic-design\\.DuplicatorUninstaller$",
            ]
end
