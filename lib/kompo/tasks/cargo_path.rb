# frozen_string_literal: true

require "open3"

module Kompo
  # Section to get the Cargo path.
  # Switches implementation based on whether Cargo is already installed.
  class CargoPath < Taski::Section
    interfaces :path

    def impl
      cargo_installed? ? Installed : Install
    end

    # Use existing Cargo installation
    class Installed < Taski::Task
      def run
        # First check PATH, then fallback to default rustup location
        cargo_in_path, = Open3.capture2("which", "cargo", err: File::NULL)
        cargo_in_path = cargo_in_path.chomp
        @path = if cargo_in_path.empty?
          File.expand_path("~/.cargo/bin/cargo")
        else
          cargo_in_path
        end
        puts "Cargo path: #{@path}"
        version_output, = Open3.capture2e(@path, "--version")
        puts "Cargo version: #{version_output.chomp}"
      end
    end

    # Install Cargo via rustup and return the path
    class Install < Taski::Task
      def run
        puts "Cargo not found. Installing via rustup..."
        system("curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y")

        @path = File.expand_path("~/.cargo/bin/cargo")
        raise "Failed to install Cargo" unless File.executable?(@path)

        puts "Cargo installed at: #{@path}"
        version_output, = Open3.capture2e(@path, "--version")
        puts "Cargo version: #{version_output.chomp}"
      end
    end

    private

    def cargo_installed?
      # Check if cargo is in PATH
      cargo_in_path, = Open3.capture2("which", "cargo", err: File::NULL)
      return true unless cargo_in_path.chomp.empty?

      # Check default rustup installation location
      home_cargo = File.expand_path("~/.cargo/bin/cargo")
      File.executable?(home_cargo)
    end
  end
end
