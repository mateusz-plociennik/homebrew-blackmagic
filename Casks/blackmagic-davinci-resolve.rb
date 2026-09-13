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

  # `Install Resolve 21.1.pkg`'s own installer check: "This installer requires Mac OS 15.0 or later".
  depends_on macos: :sequoia

  pkg "Install Resolve #{version}.pkg"

  # The pkg writes four receipts — `ManifestLite`, `ManifestPanels`, `ManifestBlackmagicRawPlayer` and
  # `ManifestFairlightAudioAccelerator` — but only the first is Resolve's own: it owns
  # `DaVinci Resolve.app`, `Blackmagic Proxy Generator Lite.app` and the Remote Monitor. The other
  # three are shared components that arrive with other Blackmagic installers too, and `pkgutil`
  # uninstalls are not reference-counted, so a `com.blackmagic-design.Manifest.*` prefix would delete
  # the control-panel and RAW-player files out from under a co-installed product. Observed, not
  # theorised: a machine with Fairlight Live on it carries `ManifestPanelsFairlightLive`,
  # `ManifestFairlightLive` and `ManifestProxyGenerator` receipts, which that prefix also matches.
  #
  # For the same reason there is no `delete:` of `/Applications/DaVinci Resolve`: that directory is
  # shared — Fairlight Live puts `Fairlight Studio Utility.app` and its own panel setup app in it. What
  # `pkgutil` leaves behind is the directory itself plus the installer's `Icon` and `.DS_Store`, which
  # is the right trade against deleting another product's apps.
  #
  # `Blackmagic Proxy Generator Lite.app` is the one path that needs deleting outright. Fairlight Live
  # ships the same bundle under its own receipt, so a machine with both installed has two receipts
  # claiming it and `pkgutil` removes only the files this one lists — which took Info.plist and the
  # binary and left 200-odd stale files behind, an app that no longer launches. A cask that installed
  # the bundle should remove the bundle; a husk is worse than either outcome, and reinstalling either
  # product restores it whole.
  uninstall pkgutil: "com.blackmagic-design.ManifestLite",
            delete:  "/Applications/Blackmagic Proxy Generator Lite.app"

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
