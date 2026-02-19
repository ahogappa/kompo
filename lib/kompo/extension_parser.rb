# frozen_string_literal: true

module Kompo
  # Pure functions for parsing native extension metadata files
  # Used by BuildNativeGem for extracting target names from Makefiles and Cargo.toml
  module ExtensionParser
    class ValidationError < StandardError; end

    # mkmf.rb uses target[/\A\w+/] for TARGET_NAME
    TARGET_NAME_PATTERN = /\A\w+\z/
    # Path segments like "cgi", "json/ext"
    PREFIX_PATTERN = /\A[\w\/]*\z/
    # Rust crate names allow hyphens
    CARGO_NAME_PATTERN = /\A[\w-]+\z/

    module_function

    # Parse Cargo.toml to extract target name
    # Prefers [lib].name over [package].name
    # @param content [String] Cargo.toml file content
    # @return [String, nil] Target name or nil if not found
    # @raise [ValidationError] if extracted name contains invalid characters
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
            lib_name = ::Regexp.last_match(1).strip
          when "package"
            package_name = ::Regexp.last_match(1).strip
          end
        end
      end

      lib_name = nil if lib_name&.empty?
      package_name = nil if package_name&.empty?
      name = lib_name || package_name
      return unless name

      unless CARGO_NAME_PATTERN.match?(name)
        raise ValidationError, "Invalid Cargo.toml target name: #{name.inspect}"
      end

      name
    end

    # Parse Makefile to extract target_prefix and TARGET_NAME
    # @param content [String] Makefile content
    # @param fallback_name [String] Name to use if TARGET_NAME not found
    # @return [Array<String>] [prefix, target_name] where prefix is empty string if not specified
    # @raise [ValidationError] if extracted values contain invalid characters
    def parse_makefile_metadata(content, fallback_name)
      raw_prefix = content.scan(/target_prefix = (.*)/).flatten.first&.strip
      prefix = raw_prefix&.gsub(%r{\A/+}, "")&.squeeze("/") || ""

      raw_target = content.scan(/TARGET_NAME = (.*)/).flatten.first&.strip
      target_name = (raw_target.nil? || raw_target.empty?) ? fallback_name : raw_target

      if target_name.nil? || target_name.empty?
        raise ValidationError, "Missing Makefile TARGET_NAME and no valid fallback_name provided"
      end

      unless TARGET_NAME_PATTERN.match?(target_name)
        raise ValidationError, "Invalid Makefile TARGET_NAME: #{target_name.inspect}"
      end

      unless PREFIX_PATTERN.match?(prefix)
        raise ValidationError, "Invalid Makefile target_prefix: #{prefix.inspect}"
      end

      [prefix, target_name]
    end
  end
end
