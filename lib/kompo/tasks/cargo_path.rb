# frozen_string_literal: true

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
        @path = Kompo.command_runner.which("cargo") || File.expand_path("~/.cargo/bin/cargo")
        puts "Cargo path: #{@path}"
        result = Kompo.command_runner.capture_all(@path, "--version")
        puts "Cargo version: #{result.chomp}"
      end
    end

    # Install Cargo via rustup and return the path
    class Install < Taski::Task
      RUSTUP_INSTALL_SCRIPT = "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"

      def run
        puts "Cargo not found. Installing via rustup..."
        Kompo.command_runner.run(
          "/bin/sh", "-c", RUSTUP_INSTALL_SCRIPT,
          error_message: "Failed to install Cargo via rustup"
        )

        @path = File.expand_path("~/.cargo/bin/cargo")
        raise "Failed to install Cargo" unless File.executable?(@path)

        puts "Cargo installed at: #{@path}"
        result = Kompo.command_runner.capture_all(@path, "--version")
        puts "Cargo version: #{result.chomp}"
      end
    end

    private

    def cargo_installed?
      # Check if cargo is in PATH
      cargo_in_path = Kompo.command_runner.which("cargo")
      return true if cargo_in_path

      # Check default rustup installation location
      home_cargo = File.expand_path("~/.cargo/bin/cargo")
      File.executable?(home_cargo)
    end
  end
end
