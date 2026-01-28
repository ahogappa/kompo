# frozen_string_literal: true

module Kompo
  # Pure functions for parsing native extension metadata files
  # Used by BuildNativeGem for extracting target names from Makefiles and Cargo.toml
  module ExtensionParser
    module_function

    # Parse Cargo.toml to extract target name
    # Prefers [lib].name over [package].name
    # @param content [String] Cargo.toml file content
    # @return [String, nil] Target name or nil if not found
    def parse_cargo_toml_target_name(content)
      current_section = nil
      lib_name = nil
      package_name = nil

      content.each_line do |line|
        line = line.strip

        # Match section headers like [package], [lib], etc.
        if line =~ /^\[([^\]]+)\]$/
          current_section = ::Regexp.last_match(1)
          next
        end

        # Match name = "value" or name = 'value'
        if line =~ /^name\s*=\s*["']([^"']+)["']$/
          case current_section
          when "lib"
            lib_name = ::Regexp.last_match(1)
          when "package"
            package_name = ::Regexp.last_match(1)
          end
        end
      end

      # Prefer [lib].name over [package].name
      lib_name || package_name
    end

    # Parse Makefile to extract target_prefix and TARGET_NAME
    # @param content [String] Makefile content
    # @param fallback_name [String] Name to use if TARGET_NAME not found
    # @return [Array<String>] [prefix, target_name] where prefix is empty string if not specified
    def parse_makefile_metadata(content, fallback_name)
      prefix = content.scan(/target_prefix = (.*)/).flatten.first&.delete_prefix("/") || ""
      target_name = content.scan(/TARGET_NAME = (.*)/).flatten.first || fallback_name
      [prefix, target_name]
    end
  end
end
