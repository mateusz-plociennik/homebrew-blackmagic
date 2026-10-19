cask "blackmagic-davinci-resolve" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "21.1"
  sha256 "bb591ba0bbe1059f818852d55094c74316540659d8f717f0a7f01643baccb6eb"

  # The free edition, which Blackmagic flag `requiresRegistration: true` — so unlike every other cask
  # in this tap so far, this one needs `~/.config/bmd-tap/config.json` filled in. `BmdConfig` explains
  # the file; the strategy reads the flag from the catalog rather than from anything stated here.
  #
  # Resolve's artifact path carries a build suffix (`v21.1-1`) that no cask can derive from a version.
  # Harmless: this URL is only ever a cache key, never fetched — but it does mean a bumped `version`
  # alone can leave the suffix stale, so check the path when bumping. See BmdDownloadStrategy.
  url "https://sw.blackmagicdesign.com/DaVinciResolve/v#{version}-1/DaVinci_Resolve_#{version}_Mac.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "DaVinci Resolve" }
  name "DaVinci Resolve"
  desc "Color grading, editing, visual effects and audio post production suite"
  homepage "https://www.blackmagicdesign.com/products/davinciresolve"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("DaVinci Resolve")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  conflicts_with cask: "blackmagic-davinci-resolve-studio"
  # `Install Resolve 21.1.pkg`'s own installer check: "This installer requires Mac OS 15.0 or later".
  depends_on macos: :sequoia

  pkg "Install Resolve #{version}.pkg"

  # Uninstall policy: do what Blackmagic's own uninstaller does, and keep receipts truthful — remove a
  # receipt (and its files) when the uninstaller removes those files, keep it when it keeps them.
  # `Uninstall Resolve.app` (on the DMG and in `/Applications/DaVinci Resolve`) is a GUI binary that
  # wraps a shell script, so it cannot run unattended; the `launchctl:`, `delete:` and `rmdir:` lines
  # below transcribe that script (21.1) line for line, bar the OFX renderer, which only Studio
  # installs. Re-check it when bumping.
  #
  # What the pkg writes, and where each piece goes:
  # - `ManifestLite`: Resolve itself, Proxy Generator Lite, the Advanced Panel daemon. Ours.
  # - `ManifestPanels`, `ManifestFairlightAudioAccelerator`, `ManifestBlackmagicRawPlayer`: only stage
  #   installer tarballs under Resolve's own `/Library/Application Support/…/DaVinci Resolve/Prereqs`.
  #   Ours. Postinstall scripts then run the nested installers, which write their own receipts:
  # - `DaVinciPanels`, `DaVinciKeyboards`, `FairlightPanels`: panel frameworks, setup apps and
  #   AdminUtility plug-ins. Panels are useless without Resolve and the vendor script removes them, so
  #   these receipts are uninstalled too — which also catches `DaVinci Control Panels/AdminUtility`,
  #   a path the vendor script still spells `DaVinci Resolve Panels/AdminUtility`.
  # - `FairlightDriver` (Fairlight Audio Accelerator kext) and `BlackmagicRaw_resolve`
  #   (`/Applications/Blackmagic RAW/*.app`): the vendor script keeps both, because Fairlight Live,
  #   Camera and RAW Player rely on them, so their receipts stay. `pkgutil` uninstalls are not
  #   reference-counted: uninstalling `BlackmagicRaw_resolve` would gut the RAW apps that Camera
  #   installs under its own receipt. The driver's postinstall moves `CrystalDriver.kext` into
  #   `/Library/Extensions`, outside any receipt, so it stays either way.
  #
  # `/Applications/DaVinci Resolve` goes whole, as the vendor script does, even though Fairlight Live
  # keeps `Fairlight Studio Utility.app` there and `FairlightDriver` keeps
  # `Uninstall Fairlight Audio Accelerator.app` there. Reinstalling Resolve or Fairlight Live restores
  # both, and `brew upgrade` reinstalls straight away.
  #
  # Two-way door: for receipt-only cleanup instead, drop `delete:` and `rmdir:` and the three panel
  # receipts. That keeps co-installed Fairlight Live intact but leaves panels and empty folders behind.
  uninstall launchctl: "com.blackmagic-design.DaVinciResolveBMDPanelDaemon",
            pkgutil:   [
              "^com\\.blackmagic-design\\.DaVinciKeyboards$",
              "^com\\.blackmagic-design\\.DaVinciPanels$",
              "^com\\.blackmagic-design\\.FairlightPanels$",
              "^com\\.blackmagic-design\\.ManifestBlackmagicRawPlayer$",
              "^com\\.blackmagic-design\\.ManifestFairlightAudioAccelerator$",
              "^com\\.blackmagic-design\\.ManifestLite$",
              "^com\\.blackmagic-design\\.ManifestPanels$",
            ],
            delete:    [
              "/Applications/Blackmagic Proxy Generator Lite.app",
              "/Applications/DaVinci Resolve",
              "/Library/Application Support/Blackmagic Design/DaVinci Resolve Advanced Panel",
              "/Library/Application Support/Blackmagic Design/DaVinci Resolve Panels/AdminUtility",
              "/Library/Frameworks/DaVinciPanelAPI.framework",
              "/Library/Frameworks/FairlightPanelAPI.framework",
              "/var/tmp/davinci_socket",
            ],
            rmdir:     "/Library/Application Support/Blackmagic Design/DaVinci Resolve Panels"

  # Resolve keeps its databases, project media and logs outside the installed tree, and losing a
  # colourist's project library to `brew uninstall` would be unforgivable — so these are `zap` only,
  # which is opt-in via `--zap`. Nothing here is shared with another Blackmagic product.
  zap trash: [
    "~/Library/Application Support/Blackmagic Design/DaVinci Resolve",
    "~/Library/Caches/Blackmagic Design/DaVinci Resolve",
    "~/Library/Preferences/com.blackmagic-design.DaVinciResolve.plist",
    "~/Library/Preferences/com.blackmagic-design.DaVinciResolveLauncher.plist",
  ]
end
