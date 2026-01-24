# frozen_string_literal: true

require 'open3'

module Kompo
  # Find native gem extensions that need to be built
  # Exports:
  #   - extensions: Array of hashes with extension info (dir_name, gem_ext_name, is_rust)
  class FindNativeExtensions < Taski::Task
    exports :extensions

    def run
      @extensions = []

      # Skip if no Gemfile
      unless CopyGemfile.gemfile_exists
        puts 'No Gemfile, no native extensions to find'
        return
      end

      ruby_version = InstallRuby.ruby_version
      ruby_build_path = InstallRuby.ruby_build_path
      ruby_install_dir = InstallRuby.ruby_install_dir
      bundle_ruby_dir = BundleInstall.bundle_ruby_dir

      # Get Init functions already defined in libruby-static
      builtin_init_funcs = get_builtin_init_functions(ruby_install_dir)

      # Find all native extensions in installed gems
      extconf_files = Dir.glob(File.join(bundle_ruby_dir, 'gems/**/extconf.rb'))

      extconf_files.each do |extconf_path|
        dir_name = File.dirname(extconf_path)
        gem_ext_name = File.basename(dir_name)

        # Skip if Init function is already defined in libruby-static
        # This catches gems like prism that are compiled into Ruby core
        init_func = "Init_#{gem_ext_name}"
        if builtin_init_funcs.include?(init_func)
          puts "skip: #{gem_ext_name} is already built into Ruby (#{init_func} found in libruby-static)"
          next
        end

        # Skip if this extension is part of Ruby standard library
        ruby_std_lib = dir_name.split('/').drop_while { |p| p != 'ext' }.join('/')
        ruby_ext_objects = Dir.glob(File.join(ruby_build_path, "ruby-#{ruby_version}", 'ext', '**', '*.o'))
        if ruby_ext_objects.any? { |o| o.include?(ruby_std_lib) }
          puts "skip: #{gem_ext_name} is included in Ruby standard library"
          next
        end

        cargo_toml = File.join(dir_name, 'Cargo.toml')
        is_rust = File.exist?(cargo_toml)

        @extensions << {
          dir_name: dir_name,
          gem_ext_name: gem_ext_name,
          is_rust: is_rust,
          cargo_toml: is_rust ? cargo_toml : nil
        }
      end

      puts "Found #{@extensions.size} native extensions to build"
    end

    private

    # Extract Init_ function names from libruby-static using nm
    def get_builtin_init_functions(ruby_install_dir)
      lib_dir = File.join(ruby_install_dir, 'lib')
      static_lib = Dir.glob(File.join(lib_dir, 'libruby*-static.a')).first
      return Set.new unless static_lib

      # Use nm to extract defined Init_ symbols (T = text/code section)
      # Use Open3.capture2 with array form to avoid shell injection
      output, status = Open3.capture2('nm', static_lib, err: File::NULL)
      return Set.new unless status.success?

      # Filter lines matching " T _?Init_" pattern and extract the symbol name
      # macOS prefixes symbols with underscore, Linux does not
      symbols = output.lines.select { |line| line.match?(/ T _?Init_/) }
      symbols.map do |line|
        # Third whitespace-separated field is the symbol name
        symbol = line.split[2]
        symbol&.delete_prefix('_')
      end.compact.to_set
    end
  end
end
