# frozen_string_literal: true

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
        @path = Kompo.command_runner.which("ruby-build")
        puts "ruby-build path: #{@path}"
        result = Kompo.command_runner.capture(@path, "--version", suppress_stderr: true)
        puts "ruby-build version: #{result.chomp}"
      end
    end

    # Install ruby-build via Homebrew (macOS)
    class FromHomebrew < Taski::Task
      def run
        brew = HomebrewPath.path
        puts "Installing ruby-build via Homebrew..."
        Kompo.command_runner.run(brew, "install", "ruby-build", error_message: "Failed to install ruby-build")

        prefix = Kompo.command_runner.capture(brew, "--prefix", "ruby-build", suppress_stderr: true).chomp
        @path = prefix + "/bin/ruby-build"
        raise "Failed to install ruby-build" unless File.executable?(@path)

        puts "ruby-build path: #{@path}"
        result = Kompo.command_runner.capture(@path, "--version", suppress_stderr: true)
        puts "ruby-build version: #{result.chomp}"
      end
    end

    # Install ruby-build via git clone (Linux)
    class FromSource < Taski::Task
      def run
        puts "ruby-build not found. Installing via git..."
        install_dir = File.expand_path("~/.ruby-build")

        if Dir.exist?(install_dir)
          Kompo.command_runner.run("git", "-C", install_dir, "pull", "--quiet")
        else
          Kompo.command_runner.run(
            "git", "clone", "https://github.com/rbenv/ruby-build.git", install_dir,
            error_message: "Failed to clone ruby-build repository"
          )
        end

        @path = File.join(install_dir, "bin", "ruby-build")
        raise "Failed to install ruby-build" unless File.executable?(@path)

        puts "ruby-build installed at: #{@path}"
        result = Kompo.command_runner.capture(@path, "--version", suppress_stderr: true)
        puts "ruby-build version: #{result.chomp}"
      end
    end

    private

    def ruby_build_installed?
      Kompo.command_runner.which("ruby-build") != nil
    end

    def darwin?
      return true if RUBY_PLATFORM.include?("darwin")
      Kompo.command_runner.capture("uname", "-s").chomp == "Darwin"
    end

    def check_homebrew_available!
      # Check if brew is in PATH
      brew_in_path = Kompo.command_runner.which("brew")
      return if brew_in_path

      # Check common Homebrew installation paths (including ARM64 at /opt/homebrew)
      return if HomebrewPath::COMMON_BREW_PATHS.any? { |p| File.executable?(p) }

      raise <<~ERROR
        Homebrew is required on macOS but not installed.
        Please install Homebrew first: https://brew.sh
      ERROR
    end
  end
end
