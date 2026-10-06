cask "blackmagic-camera" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "10.3"
  sha256 "c48ba4940074f82cd3ab3058224c44127c618b117d5d9ef3a7b2595850dcb4b3"

  url "https://sw.blackmagicdesign.com/CinemaCamera/v#{version}/Blackmagic_Camera_Setup_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "Blackmagic Camera" }
  name "Blackmagic Camera"
  desc "Camera setup utility and RAW tools for Blackmagic cameras"
  homepage "https://www.blackmagicdesign.com/support/family/professional-cameras"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("Blackmagic Camera")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on :macos

  pkg "Install Cameras #{version}.pkg"

  # Forget, rather than pkgutil-uninstall, RAW receipts: the vendor script decides which
  # shared apps Resolve still needs. Deleting their receipt payload would undo that decision.
  uninstall_postflight_steps do
    if_path_exists "/var/db/receipts/com.blackmagic-design.BlackmagicRaw.plist" do
      run "/usr/sbin/pkgutil", args: ["--forget", "com.blackmagic-design.BlackmagicRaw"], sudo: true
    end
    if_path_exists "/var/db/receipts/com.blackmagic-design.BlackmagicRawSDK.plist" do
      run "/usr/sbin/pkgutil", args: ["--forget", "com.blackmagic-design.BlackmagicRawSDK"], sudo: true
    end
  end

  # Vendor uninstall1.sh removes Cameras apps/support; uninstall4.sh also removes RAW SDK,
  # NLE plug-ins and camera datapacks, keeping RAW player apps only when Resolve uses them.
  # Comment out script to revert to receipt-only cleanup, but shared RAW files will remain.
  uninstall script:  {
              executable: "Uninstall Cameras.app/Contents/Resources/uninstall.sh",
              args:       ["", "#{staged_path}/Uninstall Cameras.app/Contents/Resources"],
              sudo:       true,
            },
            pkgutil: [
              "^com\\.blackmagic-design\\.CameraControllers$",
              "^com\\.blackmagic-design\\.Cameras$",
              "^com\\.blackmagic-design\\.CamerasAssets$",
              "^com\\.blackmagic-design\\.CamerasUninstaller$",
              "^com\\.blackmagic-design\\.MiniRecorder$",
              "^com\\.blackmagic-design\\.SMPTEFiber$",
            ]
end
