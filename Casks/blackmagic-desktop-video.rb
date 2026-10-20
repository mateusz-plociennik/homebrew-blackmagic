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

  # The vendor scripts deactivate the driver extension and remove payloads shared with Cintel and
  # Streaming. They also clear legacy receipts; reinstall products that share those files afterward.
  # Keep Homebrew's receipt list to the five exact IDs in the 16.4 installer.
  # To retain shared payloads instead, remove both scripts and the receipt patterns.
  uninstall early_script: {
              executable: "Uninstall Desktop Video.app/Contents/Resources/uninstall_uid_root.sh",
              args:       ["", "#{staged_path}/Uninstall Desktop Video.app/Contents/Resources"],
              sudo:       true,
            },
            script:       {
              executable: "Uninstall Desktop Video.app/Contents/Resources/uninstall.sh",
              args:       ["", "#{staged_path}/Uninstall Desktop Video.app/Contents/Resources"],
              sudo:       true,
            },
            pkgutil:      [
              "^com\\.blackmagic-design\\.DesktopVideo$",
              "^com\\.blackmagic-design\\.DesktopVideoAssets$",
              "^com\\.blackmagic-design\\.DesktopVideoUninstaller$",
              "^com\\.blackmagic-design\\.DiskSpeedTest$",
              "^com\\.blackmagic-design\\.MediaExpress$",
            ]
end
