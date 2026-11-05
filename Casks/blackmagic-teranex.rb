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

  # Release notes require macOS 11 Big Sur, Homebrew's macOS floor. Distribution supports arm64 and x86_64.
  depends_on :macos

  pkg "Install Teranex #{version}.pkg"

  # All four package payloads are under these paths. TeranexMini installs its setup plugins inside
  # the shared Teranex support directory; target both roots rather than forgetting Mini's receipt alone.
  uninstall quit:    "com.blackmagic-design.teranex.utility",
            pkgutil: [
              "^com\\.blackmagic-design\\.Teranex$",
              "^com\\.blackmagic-design\\.TeranexAssets$",
              "^com\\.blackmagic-design\\.TeranexMini$",
              "^com\\.blackmagic-design\\.TeranexUninstaller$",
            ],
            delete:  [
              "/Applications/Blackmagic Teranex",
              "/Library/Application Support/Blackmagic Design/Teranex",
            ]
end
