cask "blackmagic-web-presenter" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "3.5"
  sha256 "36d8c4824cd49e2a9a0d4544751f98c8afb17faf863884e1c55c7744ca168fe0"

  url "https://sw.blackmagicdesign.com/WebPresenter/v#{version}/Blackmagic_Web_Presenter_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Blackmagic Web Presenter" }
  name "Blackmagic Web Presenter"
  desc "Setup utility for Blackmagic Web Presenter hardware"
  homepage "https://www.blackmagicdesign.com/support/family/streaming-and-encoding"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Blackmagic Web Presenter")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on macos: :sonoma

  pkg "Install Web Presenter #{version}.pkg"

  # The vendor uninstaller removes the shared app and forgets the receipts Streaming uses too.
  # Leave the package payload and receipts in place so uninstalling this cask cannot break Streaming.
end
