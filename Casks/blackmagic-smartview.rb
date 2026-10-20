cask "blackmagic-smartview" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "5.0.4"
  sha256 "b1c3d5781596fedd4f8fb5693d1a0a3e406cb1c0822c5b2d536ecf3e2abb6dba"

  url "https://sw.blackmagicdesign.com/SmartView/v#{version}/Blackmagic_SmartView_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "SmartView" }
  name "SmartView"
  desc "Utility for configuring and updating Blackmagic SmartView displays"
  homepage "https://www.blackmagicdesign.com/support/family/video-and-audio-monitoring"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("SmartView")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on macos: :sonoma

  pkg "Install SmartView #{version}.pkg"

  # The vendor uninstaller forgets a broad, case-insensitive SmartView receipt prefix.
  # Remove only the package's three exact receipts and its product-owned directories instead.
  uninstall pkgutil: [
              "^com\\.blackmagic-design\\.SmartView$",
              "^com\\.blackmagic-design\\.SmartViewAssets$",
              "^com\\.blackmagic-design\\.SmartViewUninstaller$",
            ],
            delete:  [
              "/Applications/Blackmagic SmartView",
              "/Library/Application Support/Blackmagic Design/Blackmagic SmartView",
            ]

  caveats do
    "The current SmartView release downloads anonymously without a separate download-terms opt-in. " \
      "The installer includes a Blackmagic Design License Agreement; review its terms and satisfy " \
      "any applicable licensing, fee, or activation requirements."
  end
end
