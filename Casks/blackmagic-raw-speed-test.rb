cask "blackmagic-raw-speed-test" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "1.4"
  sha256 "e566c9181b00a17475dac5d7fe35578c371cb54336f25646a4faf5852a89943a"

  url "https://sw.blackmagicdesign.com/BlackmagicRAW/v#{version}/Blackmagic_RAW_Speed_Test_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Blackmagic RAW Speed Test" }
  name "Blackmagic RAW Speed Test"
  desc "CPU and GPU benchmark for Blackmagic RAW decoding"
  homepage "https://www.blackmagicdesign.com/support/family/professional-cameras"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Blackmagic RAW Speed Test")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on :macos

  app "Blackmagic RAW Speed Test.app"

  caveats do
    requires_rosetta
  end
end
