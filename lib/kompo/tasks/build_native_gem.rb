# frozen_string_literal: true

require "fileutils"
require_relative "../extension_parser"
require_relative "../cache/native_extension"

module Kompo
  # Build native gem extensions (C extensions and Rust extensions)
  # Supports caching based on Gemfile.lock hash and Ruby version
  # Exports:
  #   - exts: Array of [so_path, init_func] pairs for main.c template
  #   - exts_dir: Directory containing compiled .o files
  class BuildNativeGem < Taski::Task
    exports :exts, :exts_dir

    def run
      extensions = FindNativeExtensions.extensions
      if extensions.empty?
        @exts = Skip.exts
        @exts_dir = Skip.exts_dir
        return
      end

      # Skip cache if --no-cache is specified
      if Taski.args[:no_cache]
        @exts = FromSource.exts
        @exts_dir = FromSource.exts_dir
        return
      end

      if cache_exists?
        @exts = FromCache.exts
        @exts_dir = FromCache.exts_dir
      else
        @exts = FromSource.exts
        @exts_dir = FromSource.exts_dir
      end
    end

    # Restore native extensions from cache
    class FromCache < Taski::Task
      exports :exts, :exts_dir

      def run
        work_dir = WorkDir.path
        @exts_dir = File.join(work_dir, "ext")

        cache = build_cache
        raise "Native extension cache not found" unless cache&.exists?

        group("Restoring native extensions from cache") do
          @exts = cache.restore(work_dir)
          puts "Restored from: #{cache.cache_dir}"
          puts "Restored #{@exts.size} extension entries"
        end

        puts "Native extensions restored from cache"
      end

      def clean
        return unless @exts_dir && Dir.exist?(@exts_dir)

        FileUtils.rm_rf(@exts_dir)
        puts "Cleaned up native extensions"
      end

      private

      def build_cache
        cache_dir = Taski.args.fetch(:cache_dir, DEFAULT_CACHE_DIR)
        ruby_version = InstallRuby.ruby_version
        work_dir = WorkDir.path

        NativeExtensionCache.from_work_dir(
          cache_dir: cache_dir,
          ruby_version: ruby_version,
          work_dir: work_dir
        )
      end
    end

    # Build native extensions from source and save to cache
    class FromSource < Taski::Task
      exports :exts, :exts_dir

      def run
        @exts = []
        @exts_dir = nil

        extensions = FindNativeExtensions.extensions
        if extensions.empty?
          puts "No native extensions to build"
          return
        end

        work_dir = WorkDir.path
        @exts_dir = File.join(work_dir, "ext")

        extensions.each do |ext|
          build_extension(ext, work_dir)
        end

        puts "Completed #{@exts.size} native extensions"

        # Save to cache
        save_to_cache(work_dir)
      end

      def clean
        return unless @exts_dir && Dir.exist?(@exts_dir)

        FileUtils.rm_rf(@exts_dir)
        puts "Cleaned up native extensions"
      end

      private

      def save_to_cache(work_dir)
        return if Taski.args[:no_cache]

        cache_dir = Taski.args.fetch(:cache_dir, DEFAULT_CACHE_DIR)
        ruby_version = InstallRuby.ruby_version

        cache = NativeExtensionCache.from_work_dir(
          cache_dir: cache_dir,
          ruby_version: ruby_version,
          work_dir: work_dir
        )
        return unless cache

        group("Saving native extensions to cache") do
          cache.save(work_dir, @exts)
          puts "Saved to: #{cache.cache_dir}"
        end
      end

      def build_extension(ext, work_dir)
        dir_name = ext[:dir_name]
        gem_ext_name = ext[:gem_ext_name]

        if ext[:is_prebuilt]
          # Pre-built bundled gems only need registration for ruby_init_ext()
          group("Registering #{gem_ext_name} (pre-built bundled gem)") do
            register_prebuilt_extension(dir_name, gem_ext_name)
            puts "Registered: #{gem_ext_name}"
          end
        else
          ext_type = ext[:is_rust] ? "Rust" : "C"
          group("Building #{gem_ext_name} (#{ext_type})") do
            if ext[:is_rust]
              build_rust_extension(dir_name, ext[:cargo_toml], gem_ext_name, work_dir)
            else
              build_c_extension(dir_name, gem_ext_name, work_dir)
            end

            register_extension(dir_name, gem_ext_name)
            puts "Built: #{gem_ext_name}"
          end
        end
      end

      # Register pre-built bundled gem extension for ruby_init_ext()
      # These extensions are already compiled during Ruby build
      def register_prebuilt_extension(dir_name, gem_ext_name)
        makefile_path = File.join(dir_name, "Makefile")

        unless File.exist?(makefile_path)
          raise "Cannot register pre-built extension #{gem_ext_name}: Makefile not found in #{dir_name}"
        end

        makefile_content = File.read(makefile_path)
        prefix, target_name = ExtensionParser.parse_makefile_metadata(makefile_content, gem_ext_name)
        add_extension_entry(prefix, target_name)
      end

      def register_extension(dir_name, gem_ext_name)
        makefile_path = File.join(dir_name, "Makefile")

        if File.exist?(makefile_path)
          # C extension: parse Makefile
          makefile_content = File.read(makefile_path)
          prefix, target_name = ExtensionParser.parse_makefile_metadata(makefile_content, gem_ext_name)
        else
          # Rust extension: parse Cargo.toml
          cargo_toml_path = File.join(dir_name, "Cargo.toml")
          unless File.exist?(cargo_toml_path)
            raise "Cannot register extension #{gem_ext_name} in #{dir_name}: " \
                  "neither Makefile nor Cargo.toml found (build_rust_extension may have produced .a files)"
          end

          cargo_content = File.read(cargo_toml_path)
          prefix = "" # Rust extensions typically don't have a prefix
          target_name = ExtensionParser.parse_cargo_toml_target_name(cargo_content)
          unless target_name
            raise "Cannot determine target name for #{gem_ext_name} in #{dir_name}: " \
                  "Cargo.toml lacks [lib].name or [package].name"
          end
        end

        add_extension_entry(prefix, target_name)
      end

      # Add extension entry to @exts for ruby_init_ext()
      # ext_path must match the require path (without file extension)
      def add_extension_entry(prefix, target_name)
        ext_path = File.join(prefix, target_name).delete_prefix("/")
        @exts << [ext_path, "Init_#{target_name}"]
      end

      def build_rust_extension(dir_name, cargo_toml, gem_ext_name, work_dir)
        cargo = CargoPath.path

        puts "Building Rust extension: #{gem_ext_name}"
        # Use absolute path for --target-dir to ensure artifacts are placed correctly
        target_dir = File.join(dir_name, "target")
        command = [
          cargo,
          "rustc",
          "--release",
          "--crate-type=staticlib",
          "--target-dir", target_dir,
          "--manifest-path", cargo_toml
        ]

        Kompo.command_runner.run(*command, error_message: "Failed to build Rust extension: #{gem_ext_name}")

        # Copy .a files to ext directory
        copy_targets = Dir.glob(File.join(target_dir, "release/*.a"))
        dest_dir = FileUtils.mkdir_p(File.join(work_dir, "ext", gem_ext_name)).first
        FileUtils.cp(copy_targets, dest_dir)
      end

      def build_c_extension(dir_name, gem_ext_name, work_dir)
        puts "Building C extension: #{gem_ext_name}"

        # Run extconf.rb to generate Makefile
        # Use system Ruby so build-time dependencies (e.g., mini_portile2) are available via Bundler
        puts "Running extconf.rb in #{dir_name}"
        result = Kompo.command_runner.capture_all("ruby", "extconf.rb", chdir: dir_name)
        unless result.success?
          warn "extconf.rb failed for #{gem_ext_name}"
          warn "extconf.rb output:\n#{result.output}"
          raise "Failed to run extconf.rb for #{gem_ext_name}"
        end

        # Extract OBJS from Makefile and build
        makefile_path = File.join(dir_name, "Makefile")
        makefile_content = File.read(makefile_path)
        objs_match = makefile_content.match(/OBJS = (.*\.o)/)
        return unless objs_match

        # Get full extension path (prefix/target_name) for proper directory structure
        # This ensures erb/escape and cgi/escape are stored in different directories
        prefix, target_name = ExtensionParser.parse_makefile_metadata(makefile_content, gem_ext_name)
        ext_path = File.join(prefix, target_name).delete_prefix("/")
        dest_ext_dir = File.join(work_dir, "ext", ext_path)

        # Skip if already built
        return if Dir.exist?(dest_ext_dir)

        objs = objs_match[1]
        puts "Building objects: #{objs}"
        # Use command_runner.capture_all with array form to avoid shell injection
        make_args = ["make", "-C", dir_name] + objs.split + ["--always-make"]
        result = Kompo.command_runner.capture_all(*make_args)
        unless result.success?
          warn "make failed for #{gem_ext_name} in #{dir_name}"
          warn "Make output:\n#{result.output}"
          warn "Makefile content:\n#{makefile_content[0..500]}"
          raise "Failed to make #{gem_ext_name}"
        end

        # Copy .o files to ext directory
        copy_targets = objs.split.map { |o| File.join(dir_name, o) }
        dest_dir = FileUtils.mkdir_p(dest_ext_dir).first
        FileUtils.cp(copy_targets, dest_dir)
      end
    end

    # Skip when no native extensions
    class Skip < Taski::Task
      exports :exts, :exts_dir

      def run
        puts "No native extensions to build"
        @exts = []
        @exts_dir = nil
      end

      def clean
      end
    end

    private

    def cache_exists?
      cache_dir = Taski.args.fetch(:cache_dir, DEFAULT_CACHE_DIR)
      ruby_version = InstallRuby.ruby_version
      work_dir = WorkDir.path

      cache = NativeExtensionCache.from_work_dir(
        cache_dir: cache_dir,
        ruby_version: ruby_version,
        work_dir: work_dir
      )
      return false unless cache

      cache.exists?
    end
  end
end
