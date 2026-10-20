cask "blackmagic-ultimatte" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "2.4.1"
  sha256 "fe88227594e90900bc3a20f51d7cfcd2a488d051e225280d7687160a47598b49"

  url "https://sw.blackmagicdesign.com/Ultimatte/v#{version}/Blackmagic_Ultimatte_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Ultimatte" }
  name "Ultimatte", "Blackmagic Ultimatte Setup", "Blackmagic Ultimatte Software Control"
  desc "Setup and control software for Blackmagic Ultimatte hardware"
  homepage "https://www.blackmagicdesign.com/support/family/ultimatte"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Ultimatte")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  # The installer supports arm64 and x86_64; its 10.9 minimum is below Homebrew's supported macOS floor.
  depends_on :macos

  pkg "Install Ultimatte #{version}.pkg"

  # Blackmagic's script removes the product-owned app directory. The SmartRemote plug-in is in an
  # Ultimatte-specific support directory; forget only these four receipts, none shared with another cask.
  uninstall script:  {
              executable: "Uninstall Ultimatte.app/Contents/Resources/uninstall.sh",
              sudo:       true,
            },
            pkgutil: [
              "^com\\.blackmagic-design\\.SmartRemote$",
              "^com\\.blackmagic-design\\.Ultimatte$",
              "^com\\.blackmagic-design\\.UltimatteAssets$",
              "^com\\.blackmagic-design\\.UltimatteUninstaller$",
            ]

  caveats do
    <<~EOS
      The installer includes a Blackmagic Ultimatte license agreement. Read and accept it before installing.
      An anonymous catalog download does not grant a software license or waive applicable fees or activation
      requirements.

      After installation, connect the Ultimatte by USB and run Ultimatte Setup to update its internal software.
    EOS
  end
end
