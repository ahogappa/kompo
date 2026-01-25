# frozen_string_literal: true

require_relative "../version"

module Kompo
  # Verifies that the installed kompo-vfs version meets minimum requirements.
  # Checks the KOMPO_VFS_VERSION file in the library directory.
  module KompoVfsVersionCheck
    class IncompatibleVersionError < StandardError; end

    VERSION_FILE = "KOMPO_VFS_VERSION"

    def self.verify!(lib_path)
      actual_version = get_version(lib_path)
      required_version = Kompo::KOMPO_VFS_MIN_VERSION

      return if version_satisfies?(actual_version, required_version)

      raise IncompatibleVersionError, build_error_message(actual_version, required_version)
    end

    def self.get_version(lib_path)
      version_file = File.join(lib_path, VERSION_FILE)

      raise IncompatibleVersionError, build_missing_file_message(version_file) unless File.exist?(version_file)

      File.read(version_file).strip
    end

    def self.version_satisfies?(actual, required)
      Gem::Version.new(actual) >= Gem::Version.new(required)
    end

    def self.build_error_message(actual_version, required_version)
      <<~MSG.chomp
        kompo-vfs version #{actual_version} is too old.
        Required: >= #{required_version}

        Please upgrade:
          Homebrew: brew upgrade kompo-vfs
          Source: cd ~/.kompo/kompo-vfs && git pull && cargo build --release
      MSG
    end

    def self.build_missing_file_message(version_file)
      <<~MSG.chomp
        kompo-vfs version file not found at: #{version_file}
        Your kompo-vfs installation may be outdated (< 0.5.0).

        Please upgrade:
          Homebrew: brew upgrade kompo-vfs
          Source: cd ~/.kompo/kompo-vfs && git pull && cargo build --release
      MSG
    end
  end
end
