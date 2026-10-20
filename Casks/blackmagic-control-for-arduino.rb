cask "blackmagic-control-for-arduino" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "1.1"
  sha256 "6f8f192621eeab7289a9a7d5c66cb60549092b2f5091272b9d18652627c5a4c8"

  url "https://sw.blackmagicdesign.com/ControlForArduino/v#{version}/Blackmagic_Shield_for_Arduino_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Control for Arduino" }
  name "Control for Arduino"
  desc "Updater and Arduino library for the Blackmagic 3G-SDI Shield"
  homepage "https://www.blackmagicdesign.com/support/family/professional-cameras"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Control for Arduino")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on :macos

  pkg "Install Shield for Arduino #{version}.pkg"

  # The vendor uninstaller removes the Arduino app and support folders. Keep the package IDs exact;
  # broadening the CameraControl prefix could remove receipts belonging to another installer.
  uninstall script:  {
              executable: "Uninstall Blackmagic Shield for Arduino.app/Contents/Resources/uninstall.sh",
              sudo:       true,
            },
            pkgutil: [
              "^com\\.blackmagic-design\\.CameraControl$",
              "^com\\.blackmagic-design\\.CameraControlAssets$",
              "^com\\.blackmagic-design\\.CameraControlUninstaller$",
            ]

  caveats do
    requires_rosetta

    <<~EOS
      The installer presents Blackmagic's licence agreement for you to review and accept. Anonymous
      downloading does not grant a licence or bypass any applicable licensing or activation requirements.
    EOS
  end
end
