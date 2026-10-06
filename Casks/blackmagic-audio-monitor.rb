cask "blackmagic-audio-monitor" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "4.0.4"
  sha256 "9304d2f8c9f85375bf952b0ede26a8f908049c47b2bc2789db1fbc09e4fe7beb"

  url "https://sw.blackmagicdesign.com/AudioMonitor/v#{version}/Blackmagic_Audio_Monitor_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Blackmagic Audio Monitor" }
  name "Blackmagic Audio Monitor"
  desc "Utility for configuring and updating Blackmagic Audio Monitor hardware"
  homepage "https://www.blackmagicdesign.com/support/family/video-and-audio-monitoring"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Blackmagic Audio Monitor")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on :macos

  pkg "Install Audio Monitor #{version}.pkg"

  uninstall script:  {
              executable: "Uninstall Audio Monitor.app/Contents/Resources/uninstall.sh",
              sudo:       true,
            },
            pkgutil: [
              "^com\\.blackmagic-design\\.AudioMonitor$",
              "^com\\.blackmagic-design\\.AudioMonitorAssets$",
              "^com\\.blackmagic-design\\.AudioMonitorUninstaller$",
            ]
end
