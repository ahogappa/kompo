# frozen_string_literal: true

module Kompo
  class InstallDeps < Taski::Section
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
  end
end
