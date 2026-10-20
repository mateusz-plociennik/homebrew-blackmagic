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

casks = Dir[File.expand_path("../Casks/*.rb", __dir__)].map do |path|
  [File.basename(path), Cask::CaskLoader.load(File.read(path))]
end

check("pkgutil receipt cleanup uses explicit anchored package ids") do
  exact_receipt = /\A\^com\\\.blackmagic-design\\\.[A-Za-z0-9-]+\$\z/
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

teranex = casks.find { |file, _cask| file == "blackmagic-teranex.rb" }&.last

check("Teranex uninstalls its four bundled receipts without the vendor's broad receipt wildcard") do
  next false unless teranex

  directives = teranex.artifacts.grep(Cask::Artifact::Uninstall).fetch(0).directives
  directives.fetch(:quit) == "com.blackmagic-design.teranex.utility" &&
    directives.fetch(:script).fetch(:executable) ==
      "Uninstall Teranex.app/Contents/Resources/uninstall_uid_root.sh" &&
    directives.fetch(:script).fetch(:sudo) &&
    directives.fetch(:pkgutil) == [
      "^com\\.blackmagic-design\\.Teranex$",
      "^com\\.blackmagic-design\\.TeranexAssets$",
      "^com\\.blackmagic-design\\.TeranexMini$",
      "^com\\.blackmagic-design\\.TeranexUninstaller$",
    ]
end

report_failures!
