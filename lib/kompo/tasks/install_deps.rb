# frozen_string_literal: true

require "English"
module Kompo
  # Section to handle platform-specific dependencies.
  # Switches implementation based on the current platform.
  # Exports lib_paths for linker flags (e.g., "-L/usr/local/lib")
  class InstallDeps < Taski::Section
    interfaces :lib_paths

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
          InstallLibffi.lib_path
        ].compact.join(" ")

        puts "All Homebrew dependencies installed"
      end

      # GMP library installation Section
      class InstallGmp < Taski::Section
        interfaces :lib_path

        def impl
          brew = HomebrewPath.path
          system("#{brew} list #{BREW_NAME} > /dev/null 2>&1") ? Installed : Install
        end

        BREW_NAME = "gmp"
        MARKER_FILE = File.expand_path("~/.kompo_installed_gmp")

        class Installed < Taski::Task
          def run
            brew = HomebrewPath.path
            prefix = `#{brew} --prefix #{BREW_NAME} 2>/dev/null`.chomp
            @lib_path = "-L#{prefix}/lib" if $CHILD_STATUS.success? && !prefix.empty?
            puts "#{BREW_NAME} is already installed"
          end
        end

        class Install < Taski::Task
          def run
            brew = HomebrewPath.path
            puts "Installing #{BREW_NAME}..."
            system("#{brew} install #{BREW_NAME}") or raise "Failed to install #{BREW_NAME}"
            File.write(MARKER_FILE, "installed")

            prefix = `#{brew} --prefix #{BREW_NAME} 2>/dev/null`.chomp
            @lib_path = "-L#{prefix}/lib" if $CHILD_STATUS.success? && !prefix.empty?
          end

          def clean
            return unless File.exist?(MARKER_FILE)

            brew = HomebrewPath.path
            puts "Uninstalling #{BREW_NAME} (installed by kompo)..."
            system("#{brew} uninstall #{BREW_NAME}")
            File.delete(MARKER_FILE) if File.exist?(MARKER_FILE)
          end
        end
      end

      # OpenSSL library installation Section
      class InstallOpenssl < Taski::Section
        interfaces :lib_path

        def impl
          brew = HomebrewPath.path
          system("#{brew} list #{BREW_NAME} > /dev/null 2>&1") ? Installed : Install
        end

        BREW_NAME = "openssl@3"
        MARKER_FILE = File.expand_path("~/.kompo_installed_openssl")

        class Installed < Taski::Task
          def run
            brew = HomebrewPath.path
            prefix = `#{brew} --prefix #{BREW_NAME} 2>/dev/null`.chomp
            @lib_path = "-L#{prefix}/lib" if $CHILD_STATUS.success? && !prefix.empty?
            puts "#{BREW_NAME} is already installed"
          end
        end

        class Install < Taski::Task
          def run
            brew = HomebrewPath.path
            puts "Installing #{BREW_NAME}..."
            system("#{brew} install #{BREW_NAME}") or raise "Failed to install #{BREW_NAME}"
            File.write(MARKER_FILE, "installed")

            prefix = `#{brew} --prefix #{BREW_NAME} 2>/dev/null`.chomp
            @lib_path = "-L#{prefix}/lib" if $CHILD_STATUS.success? && !prefix.empty?
          end

          def clean
            return unless File.exist?(MARKER_FILE)

            brew = HomebrewPath.path
            puts "Uninstalling #{BREW_NAME} (installed by kompo)..."
            system("#{brew} uninstall #{BREW_NAME}")
            File.delete(MARKER_FILE) if File.exist?(MARKER_FILE)
          end
        end
      end

      # Readline library installation Section
      class InstallReadline < Taski::Section
        interfaces :lib_path

        def impl
          brew = HomebrewPath.path
          system("#{brew} list #{BREW_NAME} > /dev/null 2>&1") ? Installed : Install
        end

        BREW_NAME = "readline"
        MARKER_FILE = File.expand_path("~/.kompo_installed_readline")

        class Installed < Taski::Task
          def run
            brew = HomebrewPath.path
            prefix = `#{brew} --prefix #{BREW_NAME} 2>/dev/null`.chomp
            @lib_path = "-L#{prefix}/lib" if $CHILD_STATUS.success? && !prefix.empty?
            puts "#{BREW_NAME} is already installed"
          end
        end

        class Install < Taski::Task
          def run
            brew = HomebrewPath.path
            puts "Installing #{BREW_NAME}..."
            system("#{brew} install #{BREW_NAME}") or raise "Failed to install #{BREW_NAME}"
            File.write(MARKER_FILE, "installed")

            prefix = `#{brew} --prefix #{BREW_NAME} 2>/dev/null`.chomp
            @lib_path = "-L#{prefix}/lib" if $CHILD_STATUS.success? && !prefix.empty?
          end

          def clean
            return unless File.exist?(MARKER_FILE)

            brew = HomebrewPath.path
            puts "Uninstalling #{BREW_NAME} (installed by kompo)..."
            system("#{brew} uninstall #{BREW_NAME}")
            File.delete(MARKER_FILE) if File.exist?(MARKER_FILE)
          end
        end
      end

      # libyaml library installation Section
      class InstallLibyaml < Taski::Section
        interfaces :lib_path

        def impl
          brew = HomebrewPath.path
          system("#{brew} list #{BREW_NAME} > /dev/null 2>&1") ? Installed : Install
        end

        BREW_NAME = "libyaml"
        MARKER_FILE = File.expand_path("~/.kompo_installed_libyaml")

        class Installed < Taski::Task
          def run
            brew = HomebrewPath.path
            prefix = `#{brew} --prefix #{BREW_NAME} 2>/dev/null`.chomp
            @lib_path = "-L#{prefix}/lib" if $CHILD_STATUS.success? && !prefix.empty?
            puts "#{BREW_NAME} is already installed"
          end
        end

        class Install < Taski::Task
          def run
            brew = HomebrewPath.path
            puts "Installing #{BREW_NAME}..."
            system("#{brew} install #{BREW_NAME}") or raise "Failed to install #{BREW_NAME}"
            File.write(MARKER_FILE, "installed")

            prefix = `#{brew} --prefix #{BREW_NAME} 2>/dev/null`.chomp
            @lib_path = "-L#{prefix}/lib" if $CHILD_STATUS.success? && !prefix.empty?
          end

          def clean
            return unless File.exist?(MARKER_FILE)

            brew = HomebrewPath.path
            puts "Uninstalling #{BREW_NAME} (installed by kompo)..."
            system("#{brew} uninstall #{BREW_NAME}")
            File.delete(MARKER_FILE) if File.exist?(MARKER_FILE)
          end
        end
      end

      # zlib library installation Section
      class InstallZlib < Taski::Section
        interfaces :lib_path

        def impl
          brew = HomebrewPath.path
          system("#{brew} list #{BREW_NAME} > /dev/null 2>&1") ? Installed : Install
        end

        BREW_NAME = "zlib"
        MARKER_FILE = File.expand_path("~/.kompo_installed_zlib")

        class Installed < Taski::Task
          def run
            brew = HomebrewPath.path
            prefix = `#{brew} --prefix #{BREW_NAME} 2>/dev/null`.chomp
            @lib_path = "-L#{prefix}/lib" if $CHILD_STATUS.success? && !prefix.empty?
            puts "#{BREW_NAME} is already installed"
          end
        end

        class Install < Taski::Task
          def run
            brew = HomebrewPath.path
            puts "Installing #{BREW_NAME}..."
            system("#{brew} install #{BREW_NAME}") or raise "Failed to install #{BREW_NAME}"
            File.write(MARKER_FILE, "installed")

            prefix = `#{brew} --prefix #{BREW_NAME} 2>/dev/null`.chomp
            @lib_path = "-L#{prefix}/lib" if $CHILD_STATUS.success? && !prefix.empty?
          end

          def clean
            return unless File.exist?(MARKER_FILE)

            brew = HomebrewPath.path
            puts "Uninstalling #{BREW_NAME} (installed by kompo)..."
            system("#{brew} uninstall #{BREW_NAME}")
            File.delete(MARKER_FILE) if File.exist?(MARKER_FILE)
          end
        end
      end

      # libffi library installation Section
      class InstallLibffi < Taski::Section
        interfaces :lib_path

        def impl
          brew = HomebrewPath.path
          system("#{brew} list #{BREW_NAME} > /dev/null 2>&1") ? Installed : Install
        end

        BREW_NAME = "libffi"
        MARKER_FILE = File.expand_path("~/.kompo_installed_libffi")

        class Installed < Taski::Task
          def run
            brew = HomebrewPath.path
            prefix = `#{brew} --prefix #{BREW_NAME} 2>/dev/null`.chomp
            @lib_path = "-L#{prefix}/lib" if $CHILD_STATUS.success? && !prefix.empty?
            puts "#{BREW_NAME} is already installed"
          end
        end

        class Install < Taski::Task
          def run
            brew = HomebrewPath.path
            puts "Installing #{BREW_NAME}..."
            system("#{brew} install #{BREW_NAME}") or raise "Failed to install #{BREW_NAME}"
            File.write(MARKER_FILE, "installed")

            prefix = `#{brew} --prefix #{BREW_NAME} 2>/dev/null`.chomp
            @lib_path = "-L#{prefix}/lib" if $CHILD_STATUS.success? && !prefix.empty?
          end

          def clean
            return unless File.exist?(MARKER_FILE)

            brew = HomebrewPath.path
            puts "Uninstalling #{BREW_NAME} (installed by kompo)..."
            system("#{brew} uninstall #{BREW_NAME}")
            File.delete(MARKER_FILE) if File.exist?(MARKER_FILE)
          end
        end
      end
    end

    # Linux implementation - checks dependencies using pkg-config
    class ForLinux < Taski::Task
      def run
        unless pkg_config_available?
          puts "[WARNING] pkg-config not found. Skipping dependency check."
          puts "Install pkg-config to enable automatic dependency verification."
          @lib_paths = ""
          return
        end

        check_dependencies
        @lib_paths = collect_lib_paths

        puts "All required development libraries are installed."
      end

      REQUIRED_LIBS = {
        "openssl" => {pkg_config: "openssl", apt: "libssl-dev", yum: "openssl-devel"},
        "readline" => {pkg_config: "readline", apt: "libreadline-dev", yum: "readline-devel"},
        "zlib" => {pkg_config: "zlib", apt: "zlib1g-dev", yum: "zlib-devel"},
        "libyaml" => {pkg_config: "yaml-0.1", apt: "libyaml-dev", yum: "libyaml-devel"},
        "libffi" => {pkg_config: "libffi", apt: "libffi-dev", yum: "libffi-devel"}
      }.freeze

      private

      def pkg_config_available?
        system("which pkg-config > /dev/null 2>&1")
      end

      def check_dependencies
        missing = REQUIRED_LIBS.reject do |_, info|
          system("pkg-config --exists #{info[:pkg_config]} 2>/dev/null")
        end

        raise build_error_message(missing) unless missing.empty?
      end

      def collect_lib_paths
        pkg_names = REQUIRED_LIBS.values.map { |info| info[:pkg_config] }
        paths = pkg_names.flat_map do |pkg|
          `pkg-config --libs-only-L #{pkg} 2>/dev/null`.chomp.split
        end
        paths.uniq.join(" ")
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
