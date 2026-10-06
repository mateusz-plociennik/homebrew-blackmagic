cask "blackmagic-raw-player" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "1.4"
  sha256 "41acc64746379e4c52f9c19d617ab4aa3b37f9ebdaf06fcac8cce2fe05200dcb"

  url "https://sw.blackmagicdesign.com/BlackmagicRAW/v#{version}/Blackmagic_RAW_Player_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Blackmagic RAW Player" }
  name "Blackmagic RAW Player"
  desc "Player for Blackmagic RAW video files"
  homepage "https://www.blackmagicdesign.com/support/family/professional-cameras"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Blackmagic RAW Player")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on :macos

  app "Blackmagic RAW Player.app"

  caveats do
    requires_rosetta
  end
end
