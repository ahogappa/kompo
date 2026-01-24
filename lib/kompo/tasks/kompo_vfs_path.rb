# frozen_string_literal: true

require 'fileutils'
require_relative 'kompo_vfs_version_check'

module Kompo
  # Section to get the kompo-vfs library path.
  # Priority:
  #   1. Local directory (if specified via context[:local_kompo_vfs_path])
  #   2. Homebrew (install if needed)
  #   3. Source build (fallback if Homebrew doesn't support arch/os)
  class KompoVfsPath < Taski::Section
    interfaces :path

    def impl
      # Priority 1: Local directory if specified
      return FromLocal if Taski.args[:local_kompo_vfs_path]

      # # Priority 2: Homebrew if supported
      return FromHomebrew if homebrew_supported?

      # # Priority 3: Build from source
      FromSource
    end

    # Build from local directory (requires Cargo)
    class FromLocal < Taski::Task
      def run
        local_path = Taski.args[:local_kompo_vfs_path]
        raise 'Local kompo-vfs path not specified' unless local_path
        raise "Local kompo-vfs path does not exist: #{local_path}" unless Dir.exist?(local_path)

        puts "Building kompo-vfs from local directory: #{local_path}"
        cargo = CargoPath.path

        raise 'Failed to build kompo-vfs' unless system(cargo, 'build', '--release', chdir: local_path)

        @path = File.join(local_path, 'target', 'release')
        puts "kompo-vfs library path: #{@path}"

        KompoVfsVersionCheck.verify!(@path)
      end
    end

    # Install via Homebrew (Section to handle installed vs not installed)
    class FromHomebrew < Taski::Section
      interfaces :path

      def impl
        kompo_vfs_installed? ? Installed : Install
      end

      # Use existing Homebrew installation of kompo-vfs
      class Installed < Taski::Task
        def run
          brew = HomebrewPath.path
          @path = "#{`#{brew} --prefix kompo-vfs`.chomp}/lib"

          # Check if required library files exist (kompo-vfs >= 0.2.0 has libkompo_fs.a and libkompo_wrap.a)
          required_libs = %w[libkompo_fs.a libkompo_wrap.a]
          missing_libs = required_libs.reject { |lib| File.exist?(File.join(@path, lib)) }

          unless missing_libs.empty?
            installed_version = `#{brew} list --versions kompo-vfs`.chomp.split.last
            raise "kompo-vfs #{installed_version} is outdated. Please run: brew upgrade kompo-vfs\n" \
                  "Missing libraries: #{missing_libs.join(', ')}"
          end

          puts "kompo-vfs library path: #{@path}"

          KompoVfsVersionCheck.verify!(@path)
        end
      end

      # Install kompo-vfs via Homebrew
      class Install < Taski::Task
        def run
          brew = HomebrewPath.path
          puts 'Installing kompo-vfs via Homebrew...'
          system(brew, 'tap', 'ahogappa/kompo') or raise 'Failed to tap ahogappa/kompo'
          system(brew, 'install', 'kompo-vfs') or raise 'Failed to install kompo-vfs'

          @path = "#{`#{brew} --prefix kompo-vfs`.chomp}/lib"
          puts "kompo-vfs library path: #{@path}"

          KompoVfsVersionCheck.verify!(@path)
        end
      end

      private

      def kompo_vfs_installed?
        # Avoid calling HomebrewPath.path here to prevent duplicate dependency
        brew = `which brew 2>/dev/null`.chomp
        return false if brew.empty?

        system("#{brew} list kompo-vfs > /dev/null 2>&1")
      end
    end

    # Build from source (requires Cargo)
    class FromSource < Taski::Task
      REPO_URL = 'https://github.com/ahogappa/kompo-vfs'

      def run
        puts 'Building kompo-vfs from source...'
        cargo = CargoPath.path

        build_dir = File.expand_path('~/.kompo/kompo-vfs')
        FileUtils.mkdir_p(File.dirname(build_dir))

        if Dir.exist?(build_dir)
          system('git', '-C', build_dir, 'pull', '--quiet')
        else
          system('git', 'clone', REPO_URL, build_dir) or raise 'Failed to clone kompo-vfs repository'
        end

        system(cargo, 'build', '--release', chdir: build_dir) or raise 'Failed to build kompo-vfs'

        @path = File.join(build_dir, 'target', 'release')
        puts "kompo-vfs library path: #{@path}"

        KompoVfsVersionCheck.verify!(@path)
      end
    end

    private

    def homebrew_supported?
      # Check if current arch/os combination is supported by Homebrew formula
      arch = `uname -m`.chomp
      os = `uname -s`.chomp

      # Supported combinations (adjust based on actual formula support)
      supported = [
        %w[arm64 Darwin],
        %w[x86_64 Darwin],
        %w[x86_64 Linux]
      ]

      supported.include?([arch, os])
    end
  end
end
