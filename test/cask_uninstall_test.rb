# typed: strict
# frozen_string_literal: true

require "cask/cask_loader"
require_relative "support"

camera = Cask::CaskLoader.load(File.read(File.expand_path("../Casks/blackmagic-camera.rb", __dir__)))
uninstall = camera.artifacts.grep(Cask::Artifact::Uninstall).fetch(0)
steps = camera.artifacts.grep(Cask::Artifact::UninstallPostflightSteps).fetch(0).steps

check("Camera invokes the vendor wrapper with its resources as the second argument") do
  script = uninstall.directives.fetch(:script)
  script.fetch(:args) == ["", "#{camera.staged_path}/Uninstall Cameras.app/Contents/Resources"] &&
    script.fetch(:executable) == "Uninstall Cameras.app/Contents/Resources/uninstall.sh" && script.fetch(:sudo)
end

check("Camera receipt cleanup does not delete RAW payload the vendor might preserve") do
  patterns = uninstall.directives.fetch(:pkgutil).map { |pattern| Regexp.new(pattern) }
  raw_receipts = %w[BlackmagicRaw BlackmagicRawSDK BlackmagicRaw_resolve ManifestBlackmagicRawPlayer]
  raw_receipts.none? do |receipt|
    patterns.any? { |pattern| "com.blackmagic-design.#{receipt}".match?(pattern) }
  end
end

check("Camera forgets only the two bundled RAW receipts, guarded by their existence") do
  steps.length == 2 && steps.zip(%w[BlackmagicRaw BlackmagicRawSDK]).all? do |step, receipt|
    step.fetch("type") == "run" && step.fetch("args") == ["--forget", "com.blackmagic-design.#{receipt}"] &&
      step.fetch("sudo") && !step.fetch("allow_failure", false) &&
      step.fetch("guards").fetch(0).fetch("path") == "/var/db/receipts/com.blackmagic-design.#{receipt}.plist"
  end
end

cintel = Cask::CaskLoader.load(File.read(File.expand_path("../Casks/blackmagic-cintel.rb", __dir__)))
cintel_uninstall = cintel.artifacts.grep(Cask::Artifact::Uninstall).fetch(0).directives

check("Cintel removes both orphaned helper jobs, plists and the privileged helper") do
  cintel_uninstall.fetch(:launchctl) == [
    "com.blackmagic-design.desktopvideo.helper",
    "com.blackmagic-design.DesktopVideoDriverExtension.Helper",
  ] && cintel_uninstall.fetch(:delete) == [
    "/Library/LaunchDaemons/com.blackmagic-design.DesktopVideoDriverExtension.Helper.plist",
    "/Library/LaunchDaemons/com.blackmagic-design.DesktopVideoHelper.plist",
    "/Library/PrivilegedHelperTools/com.blackmagic-design.DesktopVideoDriverExtension.Helper",
  ]
end

egpu = Cask::CaskLoader.load(File.read(File.expand_path("../Casks/blackmagic-egpu.rb", __dir__)))
egpu_pkg = egpu.artifacts.grep(Cask::Artifact::Pkg).fetch(0)
egpu_uninstall = egpu.artifacts.grep(Cask::Artifact::Uninstall).fetch(0).directives
egpu_preflight = egpu.artifacts.grep(Cask::Artifact::PreflightSteps).fetch(0).steps.fetch(0)
egpu_uninstall_steps = egpu.artifacts.grep(Cask::Artifact::UninstallPostflightSteps).fetch(0).steps

check("eGPU installs the nested firmware updater package") do
  egpu_pkg.summarize == "Blackmagic eGPU Firmware Updater.pkg"
end

check("eGPU uninstall forgets its exact receipt without removing its files") do
  egpu_uninstall_steps.length == 1 && egpu_uninstall_steps.all? do |step|
    step.fetch("type") == "run" &&
      step.fetch("args") == ["--forget", "com.blackmagic-design.Blackmagic_eGPU_Firmware"] &&
      step.fetch("sudo") && !step.fetch("allow_failure", false) &&
      step.fetch("guards").fetch(0).fetch("path") ==
        "/var/db/receipts/com.blackmagic-design.Blackmagic_eGPU_Firmware.plist"
  end && egpu_uninstall.exclude?(:pkgutil)
end

check("eGPU uninstall removes both firmware blobs and preserves the shared plist") do
  egpu_uninstall.fetch(:delete) == [
    "/Library/ThunderboltAccessoryFirmwareUpdates/BlackmagicDesign/Blackmagic_eGPU_Pro_Thunderbolt.bin",
    "/Library/ThunderboltAccessoryFirmwareUpdates/BlackmagicDesign/Blackmagic_eGPU_Thunderbolt.bin",
  ]
end

check("eGPU preflight requires a product-specific license marker") do
  guard = egpu_preflight.fetch("guards").fetch(0)
  guard.fetch("condition") == "unless_exists" && guard.fetch("base") == "home" &&
    guard.fetch("path") == ".config/bmd-tap/agree-to-egpu-license" &&
    egpu_preflight.fetch("args").last.include?("installer license")
end

casks = Dir[File.expand_path("../Casks/*.rb", __dir__)].map do |path|
  [File.basename(path), Cask::CaskLoader.load(File.read(path))]
end

check("pkgutil receipt cleanup uses explicit anchored package ids") do
  exact_receipt = /\A\^com\\\.blackmagic-design\\\.[A-Za-z0-9_-]+\$\z/
  bad_patterns = casks.flat_map do |file, cask|
    uninstall_artifact = cask.artifacts.grep(Cask::Artifact::Uninstall).first
    pkgutil = uninstall_artifact&.directives&.fetch(:pkgutil, nil)
    next [] unless pkgutil

    Array(pkgutil).grep_v(exact_receipt).map { |pattern| "#{file}: #{pattern}" }
  end

  bad_patterns.empty? || raise(bad_patterns.join(", "))
end

check("pkgutil receipt cleanup avoids wildcard or grouped regex stanzas") do
  broad_patterns = casks.flat_map do |file, cask|
    uninstall_artifact = cask.artifacts.grep(Cask::Artifact::Uninstall).first
    pkgutil = uninstall_artifact&.directives&.fetch(:pkgutil, nil)
    next [] unless pkgutil

    Array(pkgutil).grep(/[*?|()]/).map { |pattern| "#{file}: #{pattern}" }
  end

  broad_patterns.empty? || raise(broad_patterns.join(", "))
end

report_failures!
