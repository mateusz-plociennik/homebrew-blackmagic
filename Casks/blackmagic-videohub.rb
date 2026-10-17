cask "blackmagic-videohub" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "11.0.1"
  sha256 "f5619de03c02520fac8f4e0a93ae752c7d96740229d6f44beb663b70918b5a85"

  url "https://sw.blackmagicdesign.com/Videohub/v#{version}/Blackmagic_Videohub_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Blackmagic Videohub" }
  name "Blackmagic Videohub", "Videohub Control"
  desc "Control, setup and update utilities for Videohub routers and hardware panels"
  homepage "https://www.blackmagicdesign.com/support/family/routing-and-distribution"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Blackmagic Videohub")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on macos: :sequoia

  pkg "Install Videohub #{version}.pkg"

  uninstall early_script: {
              executable: "Uninstall Videohub.app/Contents/Resources/uninstall_uid_root.sh",
              sudo:       true,
            },
            launchctl:    "com.blackmagic-design.videohub.server",
            script:       {
              executable: "Uninstall Videohub.app/Contents/Resources/uninstall.sh",
              sudo:       true,
            },
            pkgutil:      [
              "^com\\.blackmagic-design\\.SmartControl$",
              "^com\\.blackmagic-design\\.Videohub$",
              "^com\\.blackmagic-design\\.Videohub2$",
              "^com\\.blackmagic-design\\.VideohubAssets$",
              "^com\\.blackmagic-design\\.VideohubUninstaller$",
            ]
end
