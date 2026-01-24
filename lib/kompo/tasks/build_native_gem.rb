# frozen_string_literal: true

require "fileutils"
require "open3"

module Kompo
  # Build native gem extensions (C extensions and Rust extensions)
  # Exports:
  #   - exts: Array of [so_path, init_func] pairs for main.c template
  #   - exts_dir: Directory containing compiled .o files
  class BuildNativeGem < Taski::Task
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
    end

    def clean
      return unless @exts_dir && Dir.exist?(@exts_dir)

      FileUtils.rm_rf(@exts_dir)
      puts "Cleaned up native extensions"
    end

    private

    def build_extension(ext, work_dir)
      dir_name = ext[:dir_name]
      gem_ext_name = ext[:gem_ext_name]
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

    def register_extension(dir_name, gem_ext_name)
      makefile_path = File.join(dir_name, "Makefile")

      if File.exist?(makefile_path)
        # C extension: parse Makefile
        makefile_content = File.read(makefile_path)
        prefix = makefile_content.scan(/target_prefix = (.*)/).flatten.first&.delete_prefix("/") || ""
        target_name = makefile_content.scan(/TARGET_NAME = (.*)/).flatten.first || gem_ext_name
      else
        # Rust extension: parse Cargo.toml
        cargo_toml_path = File.join(dir_name, "Cargo.toml")
        unless File.exist?(cargo_toml_path)
          raise "Cannot register extension #{gem_ext_name} in #{dir_name}: " \
                "neither Makefile nor Cargo.toml found (build_rust_extension may have produced .a files)"
        end

        cargo_content = File.read(cargo_toml_path)
        prefix = "" # Rust extensions typically don't have a prefix
        target_name = parse_cargo_toml_target_name(cargo_content)
        unless target_name
          raise "Cannot determine target name for #{gem_ext_name} in #{dir_name}: " \
                "Cargo.toml lacks [lib].name or [package].name"
        end
      end

      # Path for ruby_init_ext must match require path (without file extension)
      ext_path = File.join(prefix, target_name).delete_prefix("/")
      @exts << [ext_path, "Init_#{target_name}"]
    end

    # Parse Cargo.toml to extract target name
    # Prefers [lib].name over [package].name
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

      system(*command) or raise "Failed to build Rust extension: #{gem_ext_name}"

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
      extconf_output, status = Open3.capture2e("ruby", "extconf.rb", chdir: dir_name)
      unless status.success?
        warn "extconf.rb failed for #{gem_ext_name}"
        warn "extconf.rb output:\n#{extconf_output}"
        raise "Failed to run extconf.rb for #{gem_ext_name}"
      end

      # Extract OBJS from Makefile and build
      makefile_path = File.join(dir_name, "Makefile")
      makefile_content = File.read(makefile_path)
      objs_match = makefile_content.match(/OBJS = (.*\.o)/)
      return unless objs_match

      # Get full extension path (prefix/target_name) for proper directory structure
      # This ensures erb/escape and cgi/escape are stored in different directories
      prefix = makefile_content.scan(/target_prefix = (.*)/).flatten.first&.delete_prefix("/") || ""
      target_name = makefile_content.scan(/TARGET_NAME = (.*)/).flatten.first || gem_ext_name
      ext_path = File.join(prefix, target_name).delete_prefix("/")
      dest_ext_dir = File.join(work_dir, "ext", ext_path)

      # Skip if already built
      return if Dir.exist?(dest_ext_dir)

      objs = objs_match[1]
      puts "Building objects: #{objs}"
      # Use Open3.capture2e with array form to avoid shell injection
      make_args = ["make", "-C", dir_name] + objs.split + ["--always-make"]
      make_output, status = Open3.capture2e(*make_args)
      unless status.success?
        warn "make failed for #{gem_ext_name} in #{dir_name}"
        warn "Make output:\n#{make_output}"
        warn "Makefile content:\n#{makefile_content[0..500]}"
        raise "Failed to make #{gem_ext_name}"
      end

      # Copy .o files to ext directory
      copy_targets = objs.split.map { |o| File.join(dir_name, o) }
      dest_dir = FileUtils.mkdir_p(dest_ext_dir).first
      FileUtils.cp(copy_targets, dest_dir)
    end
  end
end
