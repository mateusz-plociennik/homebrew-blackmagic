cask "blackmagic-smartview" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "5.0.5"
  sha256 "938b1ba0145ab2336b87de7bcc2014d00c481a3f521508655b281c8f2c8344c1"

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
