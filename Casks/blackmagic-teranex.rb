cask "blackmagic-teranex" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "7.1.7"
  sha256 "a6195febd8f73ade38bc1ba62c6bc579c20fcfe31ede4b5b11df362ecf79fea2"

  url "https://sw.blackmagicdesign.com/Teranex/v#{version}/Blackmagic_Teranex_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Teranex" }
  name "Teranex", "Teranex Setup"
  desc "Utility for updating Teranex and Teranex Mini hardware"
  homepage "https://www.blackmagicdesign.com/products/teranex"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Teranex")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on :macos

  pkg "Install Teranex #{version}.pkg"

  # This installer also bundles TeranexMini. Use the root helper that removes only the Teranex app
  # and support directories; the standard uninstall.sh removes receipts with a broad Teranex* wildcard.
  uninstall quit:    "com.blackmagic-design.teranex.utility",
            script:  {
              executable: "Uninstall Teranex.app/Contents/Resources/uninstall_uid_root.sh",
              sudo:       true,
            },
            pkgutil: [
              "^com\\.blackmagic-design\\.Teranex$",
              "^com\\.blackmagic-design\\.TeranexAssets$",
              "^com\\.blackmagic-design\\.TeranexMini$",
              "^com\\.blackmagic-design\\.TeranexUninstaller$",
            ]
end
