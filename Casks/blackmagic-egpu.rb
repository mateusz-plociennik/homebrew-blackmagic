cask "blackmagic-egpu" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "1.2"
  sha256 "f45a995eeefcc7b9ca340bed041e991da7401fac18ca9be8f68e7f8798ce57ef"

  url "https://sw.blackmagicdesign.com/eGPU/v#{version}/Blackmagic_eGPU_#{version}_Mac.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Blackmagic eGPU" }
  name "Blackmagic eGPU"
  desc "Firmware updater files for Blackmagic eGPU and eGPU Pro"
  homepage "https://www.blackmagicdesign.com/support/family/davinci-resolve-and-fusion"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Blackmagic eGPU")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on :macos

  pkg "Blackmagic eGPU/Blackmagic eGPU Firmware Updater.pkg"

  preflight_steps do
    unless_path_exists ".config/bmd-tap/agree-to-egpu-license", base: :home do
      run "/bin/sh", args: [
        "-c",
        'echo "Review the Blackmagic eGPU installer license. If you agree, create ' \
        "~/.config/bmd-tap/agree-to-egpu-license as described in the tap README.\" >&2; exit 1",
      ]
    end
  end

  uninstall_postflight_steps do
    if_path_exists "/var/db/receipts/com.blackmagic-design.Blackmagic_eGPU_Firmware.plist" do
      run "/usr/sbin/pkgutil", args: ["--forget", "com.blackmagic-design.Blackmagic_eGPU_Firmware"], sudo: true
    end
  end

  # Remove the two firmware payloads, but keep the shared plist that describes both eGPU models.
  uninstall delete: [
    "/Library/ThunderboltAccessoryFirmwareUpdates/BlackmagicDesign/Blackmagic_eGPU_Pro_Thunderbolt.bin",
    "/Library/ThunderboltAccessoryFirmwareUpdates/BlackmagicDesign/Blackmagic_eGPU_Thunderbolt.bin",
  ]
end
