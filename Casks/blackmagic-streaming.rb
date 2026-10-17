cask "blackmagic-streaming" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "4.2.4"
  sha256 "3d561ce51633240f2cfaa0a06afd4d93304f482fbe1a7db889a05cf680465bcf"

  url "https://sw.blackmagicdesign.com/Streaming/v#{version}/Blackmagic_Streaming_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Blackmagic Streaming" }
  name "Blackmagic Streaming"
  desc "Setup and update utility for streaming encoders, decoders and Web Presenter"
  homepage "https://www.blackmagicdesign.com/support/family/streaming-and-encoding"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Blackmagic Streaming")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on macos: :sequoia

  pkg "Install Streaming #{version}.pkg"

  uninstall script:  {
              executable: "Uninstall Streaming.app/Contents/Resources/uninstall.sh",
              sudo:       true,
            },
            pkgutil: [
              "^com\\.blackmagic-design\\.WebPresenter$",
              "^com\\.blackmagic-design\\.WebPresenterAssets$",
              "^com\\.blackmagic-design\\.WebPresenterUninstaller$",
            ]
end
