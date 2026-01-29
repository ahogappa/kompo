# frozen_string_literal: true

module Kompo
  # Manages Homebrew package operations for InstallDeps
  # Handles package installation, prefix lookup, and library path retrieval
  class BrewPackage
    attr_reader :name, :static_lib_names, :marker_file

    # @param name [String] Homebrew package name (e.g., "gmp", "openssl@3")
    # @param static_lib_names [Array<String>] Static library filenames (e.g., ["libgmp.a"])
    # @param marker_file [String] Path to marker file for tracking kompo-installed packages
    def initialize(name:, static_lib_names:, marker_file:)
      @name = name
      @static_lib_names = static_lib_names
      @marker_file = marker_file
    end

    # Check if package is installed via Homebrew
    # @param brew [String] Path to brew command
    # @return [Boolean]
    def installed?(brew)
      Kompo.command_runner.capture(brew, "list", @name, suppress_stderr: true).success?
    end

    # Get package prefix path
    # @param brew [String] Path to brew command
    # @return [String, nil] Prefix path or nil if not found
    def prefix(brew)
      result = Kompo.command_runner.capture(brew, "--prefix", @name, suppress_stderr: true)
      (result.success? && !result.chomp.empty?) ? result.chomp : nil
    end

    # Get library path flag for linker
    # @param brew [String] Path to brew command
    # @return [String, nil] -L flag or nil if not found
    def lib_path(brew)
      p = prefix(brew)
      p ? "-L#{p}/lib" : nil
    end

    # Get list of existing static library paths
    # @param brew [String] Path to brew command
    # @return [Array<String>] Paths to existing static libraries
    def static_libs(brew)
      p = prefix(brew)
      return [] unless p

      @static_lib_names.map { |name| File.join(p, "lib", name) }
        .select { |path| File.exist?(path) }
    end

    # Install package via Homebrew
    # @param brew [String] Path to brew command
    def install(brew)
      puts "Installing #{@name}..."
      Kompo.command_runner.run(brew, "install", @name, error_message: "Failed to install #{@name}")
      File.write(@marker_file, "installed")
    end

    # Uninstall package if it was installed by kompo
    # @param brew [String] Path to brew command
    def uninstall(brew)
      return unless File.exist?(@marker_file)

      puts "Uninstalling #{@name} (installed by kompo)..."
      Kompo.command_runner.run(brew, "uninstall", @name)
      File.delete(@marker_file) if File.exist?(@marker_file)
    end
  end
end
