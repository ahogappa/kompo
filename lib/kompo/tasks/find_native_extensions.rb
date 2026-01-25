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

      ruby_version = InstallRuby.ruby_version
      ruby_build_path = InstallRuby.ruby_build_path
      ruby_install_dir = InstallRuby.ruby_install_dir

      # Get Init functions already defined in libruby-static
      builtin_init_funcs = get_builtin_init_functions(ruby_install_dir)

      # Find bundled gems with native extensions (Ruby 4.0+)
      # Skip if --no-stdlib is specified (bundled gems are part of stdlib)
      no_stdlib = Taski.args.fetch(:no_stdlib, false)
      unless no_stdlib
        bundled_gems_dir = File.join(ruby_build_path, "ruby-#{ruby_version}", '.bundle', 'gems')
        find_bundled_gem_extensions(bundled_gems_dir, builtin_init_funcs)
      end

      # Skip user gems if no Gemfile
      unless CopyGemfile.gemfile_exists
        puts 'No Gemfile, skipping user gem native extensions'
        puts "Found #{@extensions.size} native extensions to build"
        return
      end

      bundle_ruby_dir = BundleInstall.bundle_ruby_dir

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

        # Skip if already added as bundled gem
        if @extensions.any? { |e| e[:gem_ext_name] == gem_ext_name }
          puts "skip: #{gem_ext_name} is already added as bundled gem"
          next
        end

        cargo_toml = File.join(dir_name, 'Cargo.toml')
        is_rust = File.exist?(cargo_toml)

        @extensions << {
          dir_name: dir_name,
          gem_ext_name: gem_ext_name,
          is_rust: is_rust,
          cargo_toml: is_rust ? cargo_toml : nil,
          is_prebuilt: false
        }
      end

      puts "Found #{@extensions.size} native extensions to build"
    end

    private

    # Find native extensions in Ruby's bundled gems directory (Ruby 4.0+)
    # These are pre-built during Ruby compilation
    def find_bundled_gem_extensions(bundled_gems_dir, builtin_init_funcs)
      return unless Dir.exist?(bundled_gems_dir)

      extconf_files = Dir.glob(File.join(bundled_gems_dir, '**/extconf.rb'))

      extconf_files.each do |extconf_path|
        dir_name = File.dirname(extconf_path)
        gem_ext_name = File.basename(dir_name)

        # Skip if Init function is already defined in libruby-static
        init_func = "Init_#{gem_ext_name}"
        if builtin_init_funcs.include?(init_func)
          puts "skip: #{gem_ext_name} is already built into Ruby (#{init_func} found in libruby-static)"
          next
        end

        # Verify that .o files exist (pre-built)
        o_files = Dir.glob(File.join(dir_name, '*.o'))
        if o_files.empty?
          puts "skip: #{gem_ext_name} has no pre-built .o files"
          next
        end

        puts "Found bundled gem extension: #{gem_ext_name} (pre-built)"
        @extensions << {
          dir_name: dir_name,
          gem_ext_name: gem_ext_name,
          is_rust: false,
          cargo_toml: nil,
          is_prebuilt: true
        }
      end
    end

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
