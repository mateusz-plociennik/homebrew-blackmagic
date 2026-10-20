cask "blackmagic-ultimatte-12" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "1.0"
  sha256 "63ceb9316caae663038d5cd3e71400ce00c3f755b44178a0e8bb2a3749dc2e7f"

  url "https://sw.blackmagicdesign.com/Ultimatte/v#{version}/Blackmagic_Ultimatte_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Ultimatte 12" }
  name "Ultimatte 12", "Ultimatte Setup"
  desc "Utility for configuring and updating Ultimatte 12 hardware"
  homepage "https://www.blackmagicdesign.com/support/family/ultimatte"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Ultimatte 12")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  conflicts_with cask: "blackmagic-ultimatte"
  depends_on :macos

  pkg "Install Ultimatte v#{version}.pkg"

  # This Intel-only app needs Rosetta 2 on Apple Silicon. Ultimatte 12 1.0 and the separate
  # Ultimatte 2.4.1 release share these receipts and /Applications/Blackmagic Ultimatte; they
  # cannot coexist. The vendor uninstaller removes that shared directory, so reinstall the other
  # release if needed.
  uninstall script:  {
              executable: "Uninstall Ultimatte.app/Contents/Resources/uninstall.sh",
              sudo:       true,
            },
            pkgutil: [
              "^com\\.blackmagic-design\\.Ultimatte$",
              "^com\\.blackmagic-design\\.UltimatteAssets$",
              "^com\\.blackmagic-design\\.UltimatteUninstaller$",
            ]
end
