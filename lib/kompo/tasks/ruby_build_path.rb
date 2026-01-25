# frozen_string_literal: true

require "open3"

module Kompo
  # Section to get the ruby-build path.
  # Priority:
  #   1. Existing ruby-build installation (via which)
  #   2. macOS: Install via Homebrew
  #   3. Linux: Install via git clone
  class RubyBuildPath < Taski::Section
    interfaces :path

    def impl
      return Installed if ruby_build_installed?

      if darwin?
        check_homebrew_available!
        return FromHomebrew
      end

      FromSource
    end

    # Use existing ruby-build installation
    class Installed < Taski::Task
      def run
        path_output, = Open3.capture2("which", "ruby-build", err: File::NULL)
        @path = path_output.chomp
        puts "ruby-build path: #{@path}"
        version_output, = Open3.capture2(@path, "--version", err: File::NULL)
        puts "ruby-build version: #{version_output.chomp}"
      end
    end

    # Install ruby-build via Homebrew (macOS)
    class FromHomebrew < Taski::Task
      def run
        brew = HomebrewPath.path
        puts "Installing ruby-build via Homebrew..."
        system(brew, "install", "ruby-build") or raise "Failed to install ruby-build"

        prefix_output, = Open3.capture2(brew, "--prefix", "ruby-build", err: File::NULL)
        @path = prefix_output.chomp + "/bin/ruby-build"
        raise "Failed to install ruby-build" unless File.executable?(@path)

        puts "ruby-build path: #{@path}"
        version_output, = Open3.capture2(@path, "--version", err: File::NULL)
        puts "ruby-build version: #{version_output.chomp}"
      end
    end

    # Install ruby-build via git clone (Linux)
    class FromSource < Taski::Task
      def run
        puts "ruby-build not found. Installing via git..."
        install_dir = File.expand_path("~/.ruby-build")

        if Dir.exist?(install_dir)
          system("git", "-C", install_dir, "pull", "--quiet")
        else
          system("git", "clone", "https://github.com/rbenv/ruby-build.git", install_dir)
        end

        @path = File.join(install_dir, "bin", "ruby-build")
        raise "Failed to install ruby-build" unless File.executable?(@path)

        puts "ruby-build installed at: #{@path}"
        version_output, = Open3.capture2(@path, "--version", err: File::NULL)
        puts "ruby-build version: #{version_output.chomp}"
      end
    end

    private

    def ruby_build_installed?
      _, status = Open3.capture2("which", "ruby-build", err: File::NULL)
      status.success?
    end

    def darwin?
      RUBY_PLATFORM.include?("darwin") || `uname -s`.chomp == "Darwin"
    end

    def check_homebrew_available!
      # Check if brew is in PATH
      brew_in_path, = Open3.capture2("which", "brew", err: File::NULL)
      return unless brew_in_path.chomp.empty?

      # Check common Homebrew installation paths (including ARM64 at /opt/homebrew)
      return if HomebrewPath::COMMON_BREW_PATHS.any? { |p| File.executable?(p) }

      raise <<~ERROR
        Homebrew is required on macOS but not installed.
        Please install Homebrew first: https://brew.sh
      ERROR
    end
  end
end
