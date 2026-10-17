cask "blackmagic-davinci-resolve-studio" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "21.1.1"
  sha256 "25ac3f6b8e3eaa617d0a9451f651d2d41dc0799512156c664b55cbb1a7cff07d"

  url "https://sw.blackmagicdesign.com/DaVinciResolve/v#{version}/DaVinci_Resolve_Studio_#{version}_Mac.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "DaVinci Resolve Studio" }
  name "DaVinci Resolve Studio"
  desc "Color grading, editing, visual effects and audio post production suite"
  homepage "https://www.blackmagicdesign.com/products/davinciresolve"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("DaVinci Resolve Studio")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  conflicts_with cask: "blackmagic-davinci-resolve"
  depends_on macos: :sequoia

  pkg "Install Resolve #{version}.pkg"

  # Same uninstall policy and receipt map as `blackmagic-davinci-resolve.rb`, which explains both.
  # Studio's own receipts are `Manifest` and `ManifestPlugin` instead of `ManifestLite`, and its
  # vendor script deletes the full Proxy Generator and the OFX renderer, not Proxy Generator Lite.
  # `FairlightDriver` and `BlackmagicRaw_resolve` receipts stay on purpose.
  uninstall launchctl: "com.blackmagic-design.DaVinciResolveBMDPanelDaemon",
            pkgutil:   [
              "^com\\.blackmagic-design\\.DaVinciKeyboards$",
              "^com\\.blackmagic-design\\.DaVinciPanels$",
              "^com\\.blackmagic-design\\.FairlightPanels$",
              "^com\\.blackmagic-design\\.Manifest$",
              "^com\\.blackmagic-design\\.ManifestBlackmagicRawPlayer$",
              "^com\\.blackmagic-design\\.ManifestFairlightAudioAccelerator$",
              "^com\\.blackmagic-design\\.ManifestPanels$",
              "^com\\.blackmagic-design\\.ManifestPlugin$",
            ],
            delete:    [
              "/Applications/Blackmagic Proxy Generator.app",
              "/Applications/DaVinci Resolve",
              "/Library/Application Support/Blackmagic Design/DaVinci Resolve Advanced Panel",
              "/Library/Application Support/Blackmagic Design/DaVinci Resolve Panels/AdminUtility",
              "/Library/Frameworks/DaVinciPanelAPI.framework",
              "/Library/Frameworks/FairlightPanelAPI.framework",
              "/Library/OFX/Plugins/DaVinci Resolve Renderer.ofx.bundle",
              "/var/tmp/davinci_socket",
            ],
            rmdir:     "/Library/Application Support/Blackmagic Design/DaVinci Resolve Panels"

  # Keep Resolve's databases and preferences unless the user explicitly opts in with `--zap`.
  zap trash: [
    "~/Library/Application Support/Blackmagic Design/DaVinci Resolve",
    "~/Library/Caches/Blackmagic Design/DaVinci Resolve",
    "~/Library/Preferences/com.blackmagic-design.DaVinciResolve.plist",
    "~/Library/Preferences/com.blackmagic-design.DaVinciResolveLauncher.plist",
  ]
end
