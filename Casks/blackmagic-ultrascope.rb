cask "blackmagic-ultrascope" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "1.8.4"
  sha256 "c0fca9b1f23fafa8c10508757b19a52cc616ee65a9fce3691b3138792c5cb10b"

  url "https://sw.blackmagicdesign.com/UltraScope/v#{version}/Blackmagic_UltraScope_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "UltraScope" }
  name "UltraScope"
  desc "Utility for monitoring and updating Blackmagic UltraScope hardware"
  homepage "https://www.blackmagicdesign.com/support/family/video-and-audio-monitoring"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("UltraScope")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  # The app and kernel extensions are Intel-only; Rosetta cannot run Intel kernel extensions.
  depends_on arch: :intel
  # The installer checks macOS 10.9; the release notes recommend macOS 10.12 or later.
  depends_on :macos

  pkg "Install UltraScope #{version}.pkg"

  # The vendor's uninstaller leaves this legacy login hook; remove it only if it still belongs to UltraScope.
  uninstall_postflight_steps do
    run "/bin/sh",
        args: ["-c", <<~'SH'],
          hook=$(/usr/bin/defaults read com.apple.loginwindow LoginHook 2>/dev/null || true)
          if [ "$hook" = '/Library/Application\ Support/Blackmagic\ Design/Blackmagic\ UltraScope/UltraScopeLoginItem.sh' ]; then
            /usr/bin/defaults delete com.apple.loginwindow LoginHook
          fi
        SH
        sudo: true
  end

  uninstall script:  {
              executable: "/Applications/Blackmagic UltraScope/Uninstall UltraScope.app/Contents/Resources/uninstall.sh",
              sudo:       true,
            },
            pkgutil: [
              "^com\\.blackmagic-design\\.UltraScope$",
              "^com\\.blackmagic-design\\.UltraScopeAssets$",
              "^com\\.blackmagic-design\\.UltraScopeUninstaller$",
            ]

  caveats do
    <<~EOS
      UltraScope requires compatible Blackmagic UltraScope hardware and a USB 3 connection. The
      upstream readme recommends 4 GB of RAM.

      This release downloads anonymously and has no registration or terms gate. Download access does
      not grant a software licence or bypass any applicable activation requirement.
    EOS
  end
end
