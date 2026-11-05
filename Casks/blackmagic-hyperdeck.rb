cask "blackmagic-hyperdeck" do
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_catalog"
  require Tap.fetch("mateusz-plociennik/blackmagic").path/"lib/bmd_download_strategy"

  version "9.0.2"
  sha256 "7022d3270190b7b12a54fa003e62e2cec3570d03216a242082207f8d347de58d"

  url "https://sw.blackmagicdesign.com/HyperDeck/v#{version}/Blackmagic_HyperDeck_Macintosh_#{version}.zip",
      using: BmdDownloadStrategy,
      data:  { "product" => "HyperDeck" }
  name "HyperDeck"
  desc "Utility for updating Blackmagic HyperDeck recorders"
  homepage "https://www.blackmagicdesign.com/support/family/disk-recorders"

  livecheck do
    url BmdCatalog::CATALOG_URL
    regex BmdCatalog.release_regex("HyperDeck")
    strategy :json, &BmdCatalog::MAC_RELEASES
  end

  depends_on :macos

  pkg "Install HyperDeck #{version}.pkg"

  avid_templates = "/Applications/Avid Media Composer/SupportingFiles/Machine_Templates"

  # The vendor script deletes receipt prefixes; use the installer's exact IDs instead. Its package
  # also copies these Avid templates outside its receipts.
  uninstall pkgutil: [
              "^com\\.blackmagic-design\\.HyperDeck$",
              "^com\\.blackmagic-design\\.HyperDeckAssets$",
              "^com\\.blackmagic-design\\.HyperDeckUninstaller$",
            ],
            delete:  [
              "#{avid_templates}/Blackmagic Design HyperDeck 24P.txt",
              "#{avid_templates}/Blackmagic Design HyperDeck NTSC.txt",
              "#{avid_templates}/Blackmagic Design HyperDeck PAL.txt",
              "/Applications/Blackmagic HyperDeck",
              "/Library/Application Support/Blackmagic Design/HyperDeck",
            ]
end
