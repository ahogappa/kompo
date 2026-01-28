# frozen_string_literal: true

module Kompo
  # Section to handle platform-specific dependencies.
  # Switches implementation based on the current platform.
  # Exports lib_paths for linker flags (e.g., "-L/usr/local/lib")
  # Exports static_libs for static library full paths (macOS only)
  class InstallDeps < Taski::Section
    interfaces :lib_paths, :static_libs

    def impl
      macos? ? ForMacOS : ForLinux
    end

    # macOS implementation - installs dependencies via Homebrew
    class ForMacOS < Taski::Task
      def run
        # HomebrewPath.path triggers Homebrew installation if not present
        @lib_paths = [
          InstallGmp.lib_path,
          InstallOpenssl.lib_path,
          InstallReadline.lib_path,
          InstallLibyaml.lib_path,
          InstallZlib.lib_path,
          InstallLibffi.lib_path,
          InstallXz.lib_path
        ].compact.join(" ")

        # Collect static library paths for static linking
        @static_libs = [
          InstallGmp.static_libs,
          InstallOpenssl.static_libs,
          InstallReadline.static_libs,
          InstallLibyaml.static_libs,
          InstallZlib.static_libs,
          InstallLibffi.static_libs,
          InstallXz.static_libs
        ].flatten.compact

        puts "All Homebrew dependencies installed"
      end

      # GMP library installation Section
      class InstallGmp < Taski::Section
        interfaces :lib_path, :static_libs

        def impl
          brew = HomebrewPath.path
          brew_package_installed?(brew, BREW_NAME) ? Installed : Install
        end

        BREW_NAME = "gmp"
        MARKER_FILE = File.expand_path("~/.kompo_installed_gmp")
        STATIC_LIB_NAMES = %w[libgmp.a].freeze

        class Installed < Taski::Task
          def run
            brew = HomebrewPath.path
            result = Kompo.command_runner.capture(brew, "--prefix", BREW_NAME, suppress_stderr: true)
            if result.success? && !result.chomp.empty?
              prefix = result.chomp
              @lib_path = "-L#{prefix}/lib"
              @static_libs = STATIC_LIB_NAMES.map { |name| File.join(prefix, "lib", name) }
                .select { |path| File.exist?(path) }
            end
            puts "#{BREW_NAME} is already installed"
          end
        end

        class Install < Taski::Task
          def run
            brew = HomebrewPath.path
            puts "Installing #{BREW_NAME}..."
            Kompo.command_runner.run(brew, "install", BREW_NAME, error_message: "Failed to install #{BREW_NAME}")
            File.write(MARKER_FILE, "installed")

            result = Kompo.command_runner.capture(brew, "--prefix", BREW_NAME, suppress_stderr: true)
            if result.success? && !result.chomp.empty?
              prefix = result.chomp
              @lib_path = "-L#{prefix}/lib"
              @static_libs = STATIC_LIB_NAMES.map { |name| File.join(prefix, "lib", name) }
                .select { |path| File.exist?(path) }
            end
          end

          def clean
            return unless File.exist?(MARKER_FILE)

            brew = HomebrewPath.path
            puts "Uninstalling #{BREW_NAME} (installed by kompo)..."
            Kompo.command_runner.run(brew, "uninstall", BREW_NAME)
            File.delete(MARKER_FILE) if File.exist?(MARKER_FILE)
          end
        end
      end

      # OpenSSL library installation Section
      class InstallOpenssl < Taski::Section
        interfaces :lib_path, :static_libs

        def impl
          brew = HomebrewPath.path
          brew_package_installed?(brew, BREW_NAME) ? Installed : Install
        end

        BREW_NAME = "openssl@3"
        MARKER_FILE = File.expand_path("~/.kompo_installed_openssl")
        STATIC_LIB_NAMES = %w[libssl.a libcrypto.a].freeze

        class Installed < Taski::Task
          def run
            brew = HomebrewPath.path
            result = Kompo.command_runner.capture(brew, "--prefix", BREW_NAME, suppress_stderr: true)
            if result.success? && !result.chomp.empty?
              prefix = result.chomp
              @lib_path = "-L#{prefix}/lib"
              @static_libs = STATIC_LIB_NAMES.map { |name| File.join(prefix, "lib", name) }
                .select { |path| File.exist?(path) }
            end
            puts "#{BREW_NAME} is already installed"
          end
        end

        class Install < Taski::Task
          def run
            brew = HomebrewPath.path
            puts "Installing #{BREW_NAME}..."
            Kompo.command_runner.run(brew, "install", BREW_NAME, error_message: "Failed to install #{BREW_NAME}")
            File.write(MARKER_FILE, "installed")

            result = Kompo.command_runner.capture(brew, "--prefix", BREW_NAME, suppress_stderr: true)
            if result.success? && !result.chomp.empty?
              prefix = result.chomp
              @lib_path = "-L#{prefix}/lib"
              @static_libs = STATIC_LIB_NAMES.map { |name| File.join(prefix, "lib", name) }
                .select { |path| File.exist?(path) }
            end
          end

          def clean
            return unless File.exist?(MARKER_FILE)

            brew = HomebrewPath.path
            puts "Uninstalling #{BREW_NAME} (installed by kompo)..."
            Kompo.command_runner.run(brew, "uninstall", BREW_NAME)
            File.delete(MARKER_FILE) if File.exist?(MARKER_FILE)
          end
        end
      end

      # Readline library installation Section
      class InstallReadline < Taski::Section
        interfaces :lib_path, :static_libs

        def impl
          brew = HomebrewPath.path
          brew_package_installed?(brew, BREW_NAME) ? Installed : Install
        end

        BREW_NAME = "readline"
        MARKER_FILE = File.expand_path("~/.kompo_installed_readline")
        STATIC_LIB_NAMES = %w[libreadline.a libhistory.a].freeze

        class Installed < Taski::Task
          def run
            brew = HomebrewPath.path
            result = Kompo.command_runner.capture(brew, "--prefix", BREW_NAME, suppress_stderr: true)
            if result.success? && !result.chomp.empty?
              prefix = result.chomp
              @lib_path = "-L#{prefix}/lib"
              @static_libs = STATIC_LIB_NAMES.map { |name| File.join(prefix, "lib", name) }
                .select { |path| File.exist?(path) }
            end
            puts "#{BREW_NAME} is already installed"
          end
        end

        class Install < Taski::Task
          def run
            brew = HomebrewPath.path
            puts "Installing #{BREW_NAME}..."
            Kompo.command_runner.run(brew, "install", BREW_NAME, error_message: "Failed to install #{BREW_NAME}")
            File.write(MARKER_FILE, "installed")

            result = Kompo.command_runner.capture(brew, "--prefix", BREW_NAME, suppress_stderr: true)
            if result.success? && !result.chomp.empty?
              prefix = result.chomp
              @lib_path = "-L#{prefix}/lib"
              @static_libs = STATIC_LIB_NAMES.map { |name| File.join(prefix, "lib", name) }
                .select { |path| File.exist?(path) }
            end
          end

          def clean
            return unless File.exist?(MARKER_FILE)

            brew = HomebrewPath.path
            puts "Uninstalling #{BREW_NAME} (installed by kompo)..."
            Kompo.command_runner.run(brew, "uninstall", BREW_NAME)
            File.delete(MARKER_FILE) if File.exist?(MARKER_FILE)
          end
        end
      end

      # libyaml library installation Section
      class InstallLibyaml < Taski::Section
        interfaces :lib_path, :static_libs

        def impl
          brew = HomebrewPath.path
          brew_package_installed?(brew, BREW_NAME) ? Installed : Install
        end

        BREW_NAME = "libyaml"
        MARKER_FILE = File.expand_path("~/.kompo_installed_libyaml")
        STATIC_LIB_NAMES = %w[libyaml.a].freeze

        class Installed < Taski::Task
          def run
            brew = HomebrewPath.path
            result = Kompo.command_runner.capture(brew, "--prefix", BREW_NAME, suppress_stderr: true)
            if result.success? && !result.chomp.empty?
              prefix = result.chomp
              @lib_path = "-L#{prefix}/lib"
              @static_libs = STATIC_LIB_NAMES.map { |name| File.join(prefix, "lib", name) }
                .select { |path| File.exist?(path) }
            end
            puts "#{BREW_NAME} is already installed"
          end
        end

        class Install < Taski::Task
          def run
            brew = HomebrewPath.path
            puts "Installing #{BREW_NAME}..."
            Kompo.command_runner.run(brew, "install", BREW_NAME, error_message: "Failed to install #{BREW_NAME}")
            File.write(MARKER_FILE, "installed")

            result = Kompo.command_runner.capture(brew, "--prefix", BREW_NAME, suppress_stderr: true)
            if result.success? && !result.chomp.empty?
              prefix = result.chomp
              @lib_path = "-L#{prefix}/lib"
              @static_libs = STATIC_LIB_NAMES.map { |name| File.join(prefix, "lib", name) }
                .select { |path| File.exist?(path) }
            end
          end

          def clean
            return unless File.exist?(MARKER_FILE)

            brew = HomebrewPath.path
            puts "Uninstalling #{BREW_NAME} (installed by kompo)..."
            Kompo.command_runner.run(brew, "uninstall", BREW_NAME)
            File.delete(MARKER_FILE) if File.exist?(MARKER_FILE)
          end
        end
      end

      # zlib library installation Section
      class InstallZlib < Taski::Section
        interfaces :lib_path, :static_libs

        def impl
          brew = HomebrewPath.path
          brew_package_installed?(brew, BREW_NAME) ? Installed : Install
        end

        BREW_NAME = "zlib"
        MARKER_FILE = File.expand_path("~/.kompo_installed_zlib")
        STATIC_LIB_NAMES = %w[libz.a].freeze

        class Installed < Taski::Task
          def run
            brew = HomebrewPath.path
            result = Kompo.command_runner.capture(brew, "--prefix", BREW_NAME, suppress_stderr: true)
            if result.success? && !result.chomp.empty?
              prefix = result.chomp
              @lib_path = "-L#{prefix}/lib"
              @static_libs = STATIC_LIB_NAMES.map { |name| File.join(prefix, "lib", name) }
                .select { |path| File.exist?(path) }
            end
            puts "#{BREW_NAME} is already installed"
          end
        end

        class Install < Taski::Task
          def run
            brew = HomebrewPath.path
            puts "Installing #{BREW_NAME}..."
            Kompo.command_runner.run(brew, "install", BREW_NAME, error_message: "Failed to install #{BREW_NAME}")
            File.write(MARKER_FILE, "installed")

            result = Kompo.command_runner.capture(brew, "--prefix", BREW_NAME, suppress_stderr: true)
            if result.success? && !result.chomp.empty?
              prefix = result.chomp
              @lib_path = "-L#{prefix}/lib"
              @static_libs = STATIC_LIB_NAMES.map { |name| File.join(prefix, "lib", name) }
                .select { |path| File.exist?(path) }
            end
          end

          def clean
            return unless File.exist?(MARKER_FILE)

            brew = HomebrewPath.path
            puts "Uninstalling #{BREW_NAME} (installed by kompo)..."
            Kompo.command_runner.run(brew, "uninstall", BREW_NAME)
            File.delete(MARKER_FILE) if File.exist?(MARKER_FILE)
          end
        end
      end

      # libffi library installation Section
      class InstallLibffi < Taski::Section
        interfaces :lib_path, :static_libs

        def impl
          brew = HomebrewPath.path
          brew_package_installed?(brew, BREW_NAME) ? Installed : Install
        end

        BREW_NAME = "libffi"
        MARKER_FILE = File.expand_path("~/.kompo_installed_libffi")
        STATIC_LIB_NAMES = %w[libffi.a].freeze

        class Installed < Taski::Task
          def run
            brew = HomebrewPath.path
            result = Kompo.command_runner.capture(brew, "--prefix", BREW_NAME, suppress_stderr: true)
            if result.success? && !result.chomp.empty?
              prefix = result.chomp
              @lib_path = "-L#{prefix}/lib"
              @static_libs = STATIC_LIB_NAMES.map { |name| File.join(prefix, "lib", name) }
                .select { |path| File.exist?(path) }
            end
            puts "#{BREW_NAME} is already installed"
          end
        end

        class Install < Taski::Task
          def run
            brew = HomebrewPath.path
            puts "Installing #{BREW_NAME}..."
            Kompo.command_runner.run(brew, "install", BREW_NAME, error_message: "Failed to install #{BREW_NAME}")
            File.write(MARKER_FILE, "installed")

            result = Kompo.command_runner.capture(brew, "--prefix", BREW_NAME, suppress_stderr: true)
            if result.success? && !result.chomp.empty?
              prefix = result.chomp
              @lib_path = "-L#{prefix}/lib"
              @static_libs = STATIC_LIB_NAMES.map { |name| File.join(prefix, "lib", name) }
                .select { |path| File.exist?(path) }
            end
          end

          def clean
            return unless File.exist?(MARKER_FILE)

            brew = HomebrewPath.path
            puts "Uninstalling #{BREW_NAME} (installed by kompo)..."
            Kompo.command_runner.run(brew, "uninstall", BREW_NAME)
            File.delete(MARKER_FILE) if File.exist?(MARKER_FILE)
          end
        end
      end

      # xz/lzma library installation Section
      class InstallXz < Taski::Section
        interfaces :lib_path, :static_libs

        def impl
          brew = HomebrewPath.path
          brew_package_installed?(brew, BREW_NAME) ? Installed : Install
        end

        BREW_NAME = "xz"
        MARKER_FILE = File.expand_path("~/.kompo_installed_xz")
        STATIC_LIB_NAMES = %w[liblzma.a].freeze

        class Installed < Taski::Task
          def run
            brew = HomebrewPath.path
            result = Kompo.command_runner.capture(brew, "--prefix", BREW_NAME, suppress_stderr: true)
            if result.success? && !result.chomp.empty?
              prefix = result.chomp
              @lib_path = "-L#{prefix}/lib"
              @static_libs = STATIC_LIB_NAMES.map { |name| File.join(prefix, "lib", name) }
                .select { |path| File.exist?(path) }
            end
            puts "#{BREW_NAME} is already installed"
          end
        end

        class Install < Taski::Task
          def run
            brew = HomebrewPath.path
            puts "Installing #{BREW_NAME}..."
            Kompo.command_runner.run(brew, "install", BREW_NAME, error_message: "Failed to install #{BREW_NAME}")
            File.write(MARKER_FILE, "installed")

            result = Kompo.command_runner.capture(brew, "--prefix", BREW_NAME, suppress_stderr: true)
            if result.success? && !result.chomp.empty?
              prefix = result.chomp
              @lib_path = "-L#{prefix}/lib"
              @static_libs = STATIC_LIB_NAMES.map { |name| File.join(prefix, "lib", name) }
                .select { |path| File.exist?(path) }
            end
          end

          def clean
            return unless File.exist?(MARKER_FILE)

            brew = HomebrewPath.path
            puts "Uninstalling #{BREW_NAME} (installed by kompo)..."
            Kompo.command_runner.run(brew, "uninstall", BREW_NAME)
            File.delete(MARKER_FILE) if File.exist?(MARKER_FILE)
          end
        end
      end

      def self.brew_package_installed?(brew, package_name)
        Kompo.command_runner.capture(brew, "list", package_name, suppress_stderr: true).success?
      end
      private_class_method :brew_package_installed?
    end

    # Linux implementation - checks dependencies using pkg-config
    class ForLinux < Taski::Task
      def run
        unless pkg_config_available?
          puts "[WARNING] pkg-config not found. Skipping dependency check."
          puts "Install pkg-config to enable automatic dependency verification."
          @lib_paths = ""
          @static_libs = []
          return
        end

        check_dependencies
        @lib_paths = collect_lib_paths
        @static_libs = collect_static_libs

        puts "All required development libraries are installed."
      end

      REQUIRED_LIBS = {
        "openssl" => {pkg_config: "openssl", apt: "libssl-dev", yum: "openssl-devel", static_libs: %w[libssl.a libcrypto.a]},
        "readline" => {pkg_config: "readline", apt: "libreadline-dev", yum: "readline-devel", static_libs: %w[libreadline.a libhistory.a]},
        "zlib" => {pkg_config: "zlib", apt: "zlib1g-dev", yum: "zlib-devel", static_libs: %w[libz.a]},
        "libyaml" => {pkg_config: "yaml-0.1", apt: "libyaml-dev", yum: "libyaml-devel", static_libs: %w[libyaml.a]},
        "libffi" => {pkg_config: "libffi", apt: "libffi-dev", yum: "libffi-devel", static_libs: %w[libffi.a]},
        "gmp" => {pkg_config: "gmp", apt: "libgmp-dev", yum: "gmp-devel", static_libs: %w[libgmp.a], optional: true},
        "liblzma" => {pkg_config: "liblzma", apt: "liblzma-dev", yum: "xz-devel", static_libs: %w[liblzma.a], optional: true}
      }.freeze

      private

      def pkg_config_available?
        Kompo.command_runner.which("pkg-config") != nil
      end

      def pkg_config_exists?(pkg_name)
        Kompo.command_runner.capture("pkg-config", "--exists", pkg_name, suppress_stderr: true).success?
      end

      def check_dependencies
        missing = REQUIRED_LIBS.reject do |_, info|
          info[:optional] || pkg_config_exists?(info[:pkg_config])
        end

        raise build_error_message(missing) unless missing.empty?
      end

      def collect_lib_paths
        pkg_names = REQUIRED_LIBS.values
          .select { |info| pkg_config_exists?(info[:pkg_config]) }
          .map { |info| info[:pkg_config] }
        paths = pkg_names.flat_map do |pkg|
          Kompo.command_runner.capture("pkg-config", "--libs-only-L", pkg, suppress_stderr: true).chomp.split
        end
        paths.uniq.join(" ")
      end

      def collect_static_libs
        static_libs = []

        REQUIRED_LIBS.each do |_, info|
          next unless pkg_config_exists?(info[:pkg_config])

          libdir = Kompo.command_runner.capture(
            "pkg-config", "--variable=libdir", info[:pkg_config],
            suppress_stderr: true
          ).chomp
          next if libdir.empty?

          info[:static_libs]&.each do |lib_name|
            lib_path = File.join(libdir, lib_name)
            static_libs << lib_path if File.exist?(lib_path)
          end
        end

        static_libs
      end

      def build_error_message(missing)
        lib_names = missing.keys.join(", ")
        apt_packages = missing.values.map { |info| info[:apt] }.join(" ")
        yum_packages = missing.values.map { |info| info[:yum] }.join(" ")

        <<~MSG
          Missing required development libraries: #{lib_names}

          Please install them using your package manager:

            Ubuntu/Debian:
              sudo apt-get update
              sudo apt-get install -y #{apt_packages}

            RHEL/CentOS/Fedora:
              sudo yum install -y #{yum_packages}
              # or: sudo dnf install -y #{yum_packages}

          After installing, run kompo again.
        MSG
      end
    end

    private

    def macos?
      RUBY_PLATFORM.include?("darwin")
    end
  end
end
