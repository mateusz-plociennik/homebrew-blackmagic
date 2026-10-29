# typed: strict
# frozen_string_literal: true

require "tmpdir"
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

ultrascope = casks.find { |file, _| file == "blackmagic-ultrascope.rb" }.last
ultrascope_uninstall = ultrascope.artifacts.grep(Cask::Artifact::Uninstall).fetch(0).directives
ultrascope_postflight = ultrascope.artifacts.grep(Cask::Artifact::UninstallPostflightSteps).fetch(0).steps

check("UltraScope runs its installed uninstaller and forgets only its exact receipts") do
  ultrascope_uninstall.fetch(:script).fetch(:executable) ==
    "/Applications/Blackmagic UltraScope/Uninstall UltraScope.app/Contents/Resources/uninstall.sh" &&
    ultrascope_uninstall.fetch(:script).fetch(:sudo) &&
    ultrascope_uninstall.fetch(:pkgutil) == [
      "^com\\.blackmagic-design\\.UltraScope$",
      "^com\\.blackmagic-design\\.UltraScopeAssets$",
      "^com\\.blackmagic-design\\.UltraScopeUninstaller$",
    ]
end

check("UltraScope removes only its own system login hook") do
  args = ultrascope_postflight.fetch(0).fetch("args")
  command = args.fetch(1)
  command.include?("defaults read com.apple.loginwindow LoginHook") &&
    command.include?("/usr/bin/sed") &&
    command.include?(
      "if [ \"$hook\" = '/Library/Application Support/Blackmagic Design/" \
      "Blackmagic UltraScope/UltraScopeLoginItem.sh' ]",
    )
end

check("UltraScope login-hook cleanup matches quoted, escaped defaults output only") do
  args = ultrascope_postflight.fetch(0).fetch("args")
  Dir.mktmpdir("ultrascope-hook-test") do |dir|
    defaults = File.join(dir, "defaults")
    log = File.join(dir, "calls")
    File.write(defaults, <<~SH)
      #!/bin/sh
      if [ "$1" = read ]; then
        printf '%s\\n' "$MOCK_LOGIN_HOOK"
      else
        printf '%s\\n' "$*" >> "$MOCK_DEFAULTS_LOG"
      fi
    SH
    File.chmod(0755, defaults)
    command = args.fetch(1).gsub("/usr/bin/defaults", defaults)
    ultra_scope_hook =
      "\"/Library/Application\\\\ Support/Blackmagic\\\\ Design/Blackmagic\\\\ UltraScope/UltraScopeLoginItem.sh\""
    unrelated_hook = "\"/Library/Application\\\\ Support/Other/OtherLoginItem.sh\""

    matches_ultrascope = system(
      { "MOCK_LOGIN_HOOK" => ultra_scope_hook, "MOCK_DEFAULTS_LOG" => log },
      "/bin/sh", "-c", command, out: File::NULL, err: File::NULL
    )
    deleted_ultrascope = File.read(log).include?("delete com.apple.loginwindow LoginHook")
    File.delete(log)

    matches_other = system(
      { "MOCK_LOGIN_HOOK" => unrelated_hook, "MOCK_DEFAULTS_LOG" => log },
      "/bin/sh", "-c", command, out: File::NULL, err: File::NULL
    )
    left_other_hook = !File.exist?(log)
    matches_ultrascope && deleted_ultrascope && matches_other && left_other_hook
  end
end

check("UltraScope documents vendor cleanup and the receipt-only alternative") do
  source = File.read(File.expand_path("../Casks/blackmagic-ultrascope.rb", __dir__))
  source.include?("removes UltraScope's app, drivers, support files and startup item") &&
    source.include?("no shared app or receipt paths") &&
    source.include?("For receipt-only cleanup, remove this script directive")
end

report_failures!
