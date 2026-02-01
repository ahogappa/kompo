# frozen_string_literal: true

require_relative "../../brew_package"

module Kompo
  class InstallDeps < Taski::Section
    # macOS implementation - installs dependencies via Homebrew
    class ForMacOS < Taski::Task
      # Package definitions for all Homebrew dependencies
      PACKAGES = {
        gmp: BrewPackage.new(
          name: "gmp",
          static_lib_names: %w[libgmp.a],
          marker_file: File.expand_path("~/.kompo_installed_gmp")
        ),
        openssl: BrewPackage.new(
          name: "openssl@3",
          static_lib_names: %w[libssl.a libcrypto.a],
          marker_file: File.expand_path("~/.kompo_installed_openssl")
        ),
        readline: BrewPackage.new(
          name: "readline",
          static_lib_names: %w[libreadline.a libhistory.a],
          marker_file: File.expand_path("~/.kompo_installed_readline")
        ),
        libyaml: BrewPackage.new(
          name: "libyaml",
          static_lib_names: %w[libyaml.a],
          marker_file: File.expand_path("~/.kompo_installed_libyaml")
        ),
        zlib: BrewPackage.new(
          name: "zlib",
          static_lib_names: %w[libz.a],
          marker_file: File.expand_path("~/.kompo_installed_zlib")
        ),
        libffi: BrewPackage.new(
          name: "libffi",
          static_lib_names: %w[libffi.a],
          marker_file: File.expand_path("~/.kompo_installed_libffi")
        ),
        xz: BrewPackage.new(
          name: "xz",
          static_lib_names: %w[liblzma.a],
          marker_file: File.expand_path("~/.kompo_installed_xz")
        )
      }.freeze

      def run
        brew = HomebrewPath.path
        lib_paths = []
        static_libs = []

        PACKAGES.each_value do |package|
          if package.installed?(brew)
            puts "#{package.name} is already installed"
          else
            package.install(brew)
          end
          lib_paths << package.lib_path(brew)
          static_libs.concat(package.static_libs(brew))
        end

        @lib_paths = lib_paths.compact.join(" ")
        @static_libs = static_libs.flatten.compact
        puts "All Homebrew dependencies installed"
      end

      def clean
        brew = HomebrewPath.path
        PACKAGES.each_value do |package|
          package.uninstall(brew)
        end
      end
    end
  end
end
