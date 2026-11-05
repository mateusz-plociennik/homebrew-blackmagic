cask "blackmagic-converters" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "12.4.1"
  sha256 "5811c097c32445afd257ac3cfacbd16b74e6e24ea906d52f5ef9ed146dffc828"

  url "https://sw.blackmagicdesign.com/Converters/v#{version}/Blackmagic_Converters_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Blackmagic Converters" }
  name "Blackmagic Converters"
  desc "Utility for updating and managing Blackmagic converters"
  homepage "https://www.blackmagicdesign.com/support/family/broadcast-and-atem-converters"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Blackmagic Converters")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on :macos

  pkg "Install Converters #{version}.pkg"

  uninstall script:  {
              executable: "Uninstall Converters.app/Contents/Resources/uninstall.sh",
              sudo:       true,
            },
            pkgutil: [
              "^com\\.blackmagic-design\\.Converters$",
              "^com\\.blackmagic-design\\.ConvertersAssets$",
              "^com\\.blackmagic-design\\.ConvertersUninstaller$",
              "^com\\.blackmagic-design\\.IPVideo2$",
              "^com\\.blackmagic-design\\.MicConverter$",
              "^com\\.blackmagic-design\\.MicroConverters$",
            ]
end
