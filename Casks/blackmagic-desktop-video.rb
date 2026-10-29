cask "blackmagic-desktop-video" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "16.4"
  sha256 "4bbd73596c32ad101b493d1a4e9fc6ebfe55b7357cbb106eed4de837de7197b8"

  url "https://sw.blackmagicdesign.com/DesktopVideo/v#{version}/Blackmagic_Desktop_Video_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Desktop Video" }
  name "Desktop Video"
  desc "Video capture and playback software for Blackmagic hardware"
  homepage "https://www.blackmagicdesign.com/support/family/capture-and-playback"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Desktop Video")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on macos: :sequoia

  pkg "Install Desktop Video #{version}.pkg"

  # The vendor uninstaller also removes drivers, apps and helpers shared with Cintel and Streaming.
  # Forget only this cask's uninstaller receipt and remove its manuals and uninstaller app; retain the
  # shared runtime receipts and payloads to preserve those products' shared components.
  uninstall pkgutil: "^com\\.blackmagic-design\\.DesktopVideoUninstaller$",
            delete:  [
              "/Applications/Blackmagic Desktop Video/Documents",
              "/Applications/Blackmagic Desktop Video/Uninstall Desktop Video.app",
            ]
end
