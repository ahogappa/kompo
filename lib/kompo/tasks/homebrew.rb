# frozen_string_literal: true

require 'open3'

module Kompo
  # Section to get the Homebrew path.
  # Switches implementation based on whether Homebrew is already installed.
  class HomebrewPath < Taski::Section
    interfaces :path

    # Common Homebrew installation paths
    COMMON_BREW_PATHS = ['/opt/homebrew/bin/brew', '/usr/local/bin/brew'].freeze

    def impl
      homebrew_installed? ? Installed : Install
    end

    # Use existing Homebrew installation
    class Installed < Taski::Task
      def run
        # First check PATH
        brew_in_path, = Open3.capture2('which', 'brew', err: File::NULL)
        brew_in_path = brew_in_path.chomp
        @path = if brew_in_path.empty?
                  # Fallback to common installation paths
                  HomebrewPath::COMMON_BREW_PATHS.find { |p| File.executable?(p) }
                else
                  brew_in_path
                end
        puts "Homebrew path: #{@path}"
      end
    end

    # Install Homebrew
    class Install < Taski::Task
      MARKER_FILE = File.expand_path('~/.kompo_installed_homebrew')

      def run
        puts 'Homebrew not found. Installing...'
        system('/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"')

        brew_in_path, = Open3.capture2('which', 'brew', err: File::NULL)
        @path = brew_in_path.chomp
        if @path.empty?
          # Check common installation paths
          HomebrewPath::COMMON_BREW_PATHS.each do |p|
            if File.executable?(p)
              @path = p
              break
            end
          end
        end

        raise 'Failed to install Homebrew' if @path.nil? || @path.empty?

        # Mark that kompo installed Homebrew
        File.write(MARKER_FILE, @path)
        puts "Homebrew installed at: #{@path}"
      end

      def clean
        # Only uninstall if kompo installed it
        return unless File.exist?(MARKER_FILE)

        puts 'Uninstalling Homebrew (installed by kompo)...'
        system('NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"')
        File.delete(MARKER_FILE) if File.exist?(MARKER_FILE)
        puts 'Homebrew uninstalled'
      end
    end

    private

    def homebrew_installed?
      # Check if brew is in PATH
      brew_in_path, = Open3.capture2('which', 'brew', err: File::NULL)
      return true unless brew_in_path.chomp.empty?

      # Check common installation paths
      COMMON_BREW_PATHS.any? { |p| File.executable?(p) }
    end
  end
end
