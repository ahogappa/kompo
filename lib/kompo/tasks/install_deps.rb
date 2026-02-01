# frozen_string_literal: true

module Kompo
  # Section to handle platform-specific dependencies.
  # Switches implementation based on the current platform.
  # Exports lib_paths for linker flags (e.g., "-L/usr/local/lib")
  # Exports static_libs for static library full paths (macOS only)
  class InstallDeps < Taski::Section
    autoload :ForMacOS, "kompo/tasks/install_deps/macos"
    autoload :ForLinux, "kompo/tasks/install_deps/linux"

    interfaces :lib_paths, :static_libs

    def impl
      Kompo.macos? ? ForMacOS : ForLinux
    end
  end
end
