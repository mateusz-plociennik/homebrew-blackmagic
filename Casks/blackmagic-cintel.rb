cask "blackmagic-cintel" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "7.0"
  sha256 "362e4f8dce6861d1ce36615d2acbcf2706636083341738eb507a2f57910a1f42"

  url "https://sw.blackmagicdesign.com/Cintel/v#{version}/Blackmagic_Cintel_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Blackmagic Cintel" }
  name "Blackmagic Cintel"
  desc "Software for operating Blackmagic Cintel film scanners"
  homepage "https://www.blackmagicdesign.com/support/family/cintel"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Blackmagic Cintel")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  conflicts_with cask: "blackmagic-decklink"
  depends_on :macos

  pkg "Install Cintel #{version}.pkg"

  # Vendor uninstall1.sh removes Cintel apps/support/prefPane. uninstall2.sh also removes
  # Desktop Video drivers, NLE plug-ins and support; uninstall_uid_root2.sh unloads its
  # six launch daemons and deactivates its driver extension before deleting Desktop Video.
  # Full vendor cleanup intentionally removes shared Desktop Video components too.
  # To keep those, disable installer choice5 and remove both script directives and
  # the DesktopVideo/MediaExpress/DiskSpeedTest receipt patterns together.
  # Vendor cleanup leaves DesktopVideoHelper and a plist created by driver deactivation.
  # Remove both helper jobs/files explicitly, including an orphaned privileged helper.
  uninstall early_script: {
              executable: "Uninstall Cintel.app/Contents/Resources/uninstall_uid_root.sh",
              args:       ["", "#{staged_path}/Uninstall Cintel.app/Contents/Resources"],
              sudo:       true,
            },
            launchctl:    [
              "com.blackmagic-design.desktopvideo.helper",
              "com.blackmagic-design.DesktopVideoDriverExtension.Helper",
            ],
            script:       {
              executable: "Uninstall Cintel.app/Contents/Resources/uninstall.sh",
              args:       ["", "#{staged_path}/Uninstall Cintel.app/Contents/Resources"],
              sudo:       true,
            },
            pkgutil:      [
              "^com\\.blackmagic-design\\.Cintel$",
              "^com\\.blackmagic-design\\.CintelAssets$",
              "^com\\.blackmagic-design\\.CintelUninstaller$",
              "^com\\.blackmagic-design\\.DesktopVideo$",
              "^com\\.blackmagic-design\\.DesktopVideoAssets$",
              "^com\\.blackmagic-design\\.DesktopVideoUninstaller$",
              "^com\\.blackmagic-design\\.DiskSpeedTest$",
              "^com\\.blackmagic-design\\.MediaExpress$",
            ],
            delete:       [
              "/Library/LaunchDaemons/com.blackmagic-design.DesktopVideoDriverExtension.Helper.plist",
              "/Library/LaunchDaemons/com.blackmagic-design.DesktopVideoHelper.plist",
              "/Library/PrivilegedHelperTools/com.blackmagic-design.DesktopVideoDriverExtension.Helper",
            ]
end
