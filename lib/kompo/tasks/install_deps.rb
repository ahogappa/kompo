# frozen_string_literal: true

module Kompo
  # Task to handle platform-specific dependencies.
  # Switches implementation based on the current platform.
  # Exports lib_paths for linker flags (e.g., "-L/usr/local/lib")
  # Exports static_libs for static library full paths (macOS only)
  class InstallDeps < Taski::Task
    autoload :ForMacOS, "kompo/tasks/install_deps/macos"
    autoload :ForLinux, "kompo/tasks/install_deps/linux"

    exports :lib_paths, :static_libs

    def run
      if Kompo.macos?
        @lib_paths = ForMacOS.lib_paths
        @static_libs = ForMacOS.static_libs
      else
        @lib_paths = ForLinux.lib_paths
        @static_libs = ForLinux.static_libs
      end
    end
  end
end
