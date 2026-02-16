# frozen_string_literal: true

require "fileutils"
require "open-uri"
require_relative "kompo_vfs_version_check"

module Kompo
  # Task to get the kompo-vfs library path.
  # Priority:
  #   1. Local directory (if specified via context[:local_kompo_vfs_path])
  #   2. macOS: Homebrew (if available)
  #   3. Linux: Build from source (if cargo available)
  #   4. FromGitHubRelease (fallback)
  class KompoVfsPath < Taski::Task
    exports :path

    def run
      # Priority 1: Local directory if specified
      if Taski.args[:local_kompo_vfs_path]
        @path = FromLocal.path
        return
      end

      # Priority 2: macOS Homebrew
      if darwin? && homebrew_available?
        @path = FromHomebrew.path
        return
      end

      # Priority 3: Linux build from source
      if !darwin? && cargo_available?
        @path = FromSource.path
        return
      end

      # Priority 4: Download from GitHub Releases
      @path = FromGitHubRelease.path
    end

    # Build from local directory (requires Cargo)
    class FromLocal < Taski::Task
      exports :path

      def run
        local_path = Taski.args[:local_kompo_vfs_path]
        raise "Local kompo-vfs path not specified" unless local_path
        raise "Local kompo-vfs path does not exist: #{local_path}" unless Dir.exist?(local_path)

        puts "Building kompo-vfs from local directory: #{local_path}"
        cargo = CargoPath.path

        Kompo.command_runner.run(
          cargo, "build", "--release",
          chdir: local_path,
          error_message: "Failed to build kompo-vfs"
        )

        @path = File.join(local_path, "target", "release")
        puts "kompo-vfs library path: #{@path}"

        KompoVfsVersionCheck.verify!(@path)
      end
    end

    # Install via Homebrew (Task to handle installed vs not installed)
    class FromHomebrew < Taski::Task
      exports :path

      def run
        @path = if kompo_vfs_installed?
          Installed.path
        else
          Install.path
        end
      end

      # Use existing Homebrew installation of kompo-vfs
      class Installed < Taski::Task
        exports :path

        def run
          brew = HomebrewPath.path
          prefix = Kompo.command_runner.capture(brew, "--prefix", "kompo-vfs").chomp
          @path = "#{prefix}/lib"

          # Check if required library files exist (kompo-vfs >= 0.2.0 has libkompo_fs.a and libkompo_wrap.a)
          required_libs = %w[libkompo_fs.a libkompo_wrap.a]
          missing_libs = required_libs.reject { |lib| File.exist?(File.join(@path, lib)) }

          unless missing_libs.empty?
            installed_version = Kompo.command_runner.capture(brew, "list", "--versions", "kompo-vfs").chomp.split.last
            raise "kompo-vfs #{installed_version} is outdated. Please run: brew upgrade kompo-vfs\n" \
                  "Missing libraries: #{missing_libs.join(", ")}"
          end

          puts "kompo-vfs library path: #{@path}"

          KompoVfsVersionCheck.verify!(@path)
        end
      end

      # Install kompo-vfs via Homebrew
      class Install < Taski::Task
        exports :path

        def run
          brew = HomebrewPath.path
          puts "Installing kompo-vfs via Homebrew..."
          Kompo.command_runner.run(
            brew, "tap", "ahogappa/kompo-vfs", "https://github.com/ahogappa/kompo-vfs.git",
            error_message: "Failed to tap ahogappa/kompo-vfs"
          )
          Kompo.command_runner.run(
            brew, "install", "ahogappa/kompo-vfs/kompo-vfs",
            error_message: "Failed to install kompo-vfs"
          )

          prefix = Kompo.command_runner.capture(brew, "--prefix", "kompo-vfs").chomp
          @path = "#{prefix}/lib"
          puts "kompo-vfs library path: #{@path}"

          KompoVfsVersionCheck.verify!(@path)
        end
      end

      private

      def kompo_vfs_installed?
        # Avoid calling HomebrewPath.path here to prevent duplicate dependency
        brew = Kompo.command_runner.which("brew")
        return false unless brew

        Kompo.command_runner.capture(brew, "list", "kompo-vfs", suppress_stderr: true).success?
      end
    end

    # Build from source (requires Cargo)
    class FromSource < Taski::Task
      exports :path

      REPO_URL = "https://github.com/ahogappa/kompo-vfs"

      def run
        puts "Building kompo-vfs from source..."
        cargo = CargoPath.path

        build_dir = File.expand_path("~/.kompo/kompo-vfs")
        FileUtils.mkdir_p(File.dirname(build_dir))

        if Dir.exist?(build_dir)
          Kompo.command_runner.run("git", "-C", build_dir, "pull", "--quiet")
        else
          Kompo.command_runner.run(
            "git", "clone", REPO_URL, build_dir,
            error_message: "Failed to clone kompo-vfs repository"
          )
        end

        Kompo.command_runner.run(
          cargo, "build", "--release",
          chdir: build_dir,
          error_message: "Failed to build kompo-vfs"
        )

        @path = File.join(build_dir, "target", "release")
        puts "kompo-vfs library path: #{@path}"

        KompoVfsVersionCheck.verify!(@path)
      end
    end

    # Download prebuilt binaries from GitHub Releases
    class FromGitHubRelease < Taski::Task
      exports :path

      REPO = "ahogappa/kompo-vfs"
      REQUIRED_LIBS = %w[libkompo_fs.a libkompo_wrap.a].freeze

      class << self
        attr_writer :base_dir

        def base_dir
          @base_dir || File.join(Dir.home, ".kompo")
        end
      end

      def run
        os = detect_os
        arch = detect_arch
        lib_dir = install_dir(os, arch)

        unless already_installed?(lib_dir)
          url = download_url(os, arch)
          download_and_extract(url, os, arch)
        end

        @path = lib_dir
        puts "kompo-vfs library path: #{@path}"

        KompoVfsVersionCheck.verify!(@path)
      end

      private

      def detect_os
        if RUBY_PLATFORM.include?("darwin")
          "darwin"
        else
          "linux"
        end
      end

      def detect_arch
        cpu = RbConfig::CONFIG["host_cpu"]
        case cpu
        when /aarch64|arm64/
          "arm64"
        when /x86_64|x64/
          "x86_64"
        else
          cpu
        end
      end

      def download_url(os, arch)
        version = Kompo::KOMPO_VFS_MIN_VERSION
        "https://github.com/#{REPO}/releases/download/v#{version}/kompo-vfs-v#{version}-#{os}-#{arch}.tar.gz"
      end

      def install_dir(os, arch)
        version = Kompo::KOMPO_VFS_MIN_VERSION
        File.join(self.class.base_dir, "kompo-vfs-v#{version}-#{os}-#{arch}", "lib")
      end

      def already_installed?(lib_dir)
        REQUIRED_LIBS.all? { |lib| File.exist?(File.join(lib_dir, lib)) }
      end

      def download_and_extract(url, os, arch)
        version = Kompo::KOMPO_VFS_MIN_VERSION
        base_dir = self.class.base_dir
        FileUtils.mkdir_p(base_dir)

        tarball = File.join(base_dir, "kompo-vfs-v#{version}-#{os}-#{arch}.tar.gz")

        puts "Downloading kompo-vfs from #{url}..."
        begin
          URI.open(url) do |remote| # rubocop:disable Security/Open
            File.binwrite(tarball, remote.read)
          end
        rescue OpenURI::HTTPError => e
          raise "Failed to download kompo-vfs from #{url} (#{e.message}). " \
                "The release v#{version} may not exist for #{os}-#{arch}. " \
                "Check https://github.com/#{REPO}/releases for available platforms."
        rescue => e # rubocop:disable Style/RescueStandardError
          raise "Failed to download kompo-vfs from #{url}: #{e.message}"
        end

        puts "Extracting..."
        Kompo.command_runner.run(
          "tar", "xzf", tarball, "-C", base_dir,
          error_message: "Failed to extract kompo-vfs tarball"
        )

        FileUtils.rm_f(tarball)
      end
    end

    private

    def darwin?
      return true if RUBY_PLATFORM.include?("darwin")
      Kompo.command_runner.capture("uname", "-s").chomp == "Darwin"
    end

    def homebrew_available?
      brew_in_path = Kompo.command_runner.which("brew")
      return true if brew_in_path

      HomebrewPath::COMMON_BREW_PATHS.any? { |p| File.executable?(p) }
    end

    def cargo_available?
      !!Kompo.command_runner.which("cargo")
    end
  end
end
