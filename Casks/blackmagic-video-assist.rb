cask "blackmagic-video-assist" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "3.23"
  sha256 "ebe5e88877f15dcdc214ad400bbb4094b10be8ca209bd8ed40a2db54fae6698e"

  url "https://sw.blackmagicdesign.com/VideoAssist/v#{version}/Blackmagic_Video_Assist_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Blackmagic Video Assist" }
  name "Blackmagic Video Assist"
  desc "Utility for updating Blackmagic Video Assist software"
  homepage "https://www.blackmagicdesign.com/support/family/disk-recorders"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Blackmagic Video Assist")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on macos: :big_sur

  pkg "Install Video Assist #{version}.pkg"

  uninstall pkgutil: "(?:com\\.blackmagic\\-design\\.VideoAssist|com\\.blackmagic\\-design\\.BlackmagicRaw|com\\.blackmagic\\-design\\.BlackmagicRawSDK|com\\.blackmagic\\-design\\.VideoAssistAssets|com\\.blackmagic\\-design\\.VideoAssistUninstaller)",
            delete:  "/Applications/Blackmagic Video Assist"
end
