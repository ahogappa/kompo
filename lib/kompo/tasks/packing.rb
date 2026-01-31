# frozen_string_literal: true

require "shellwords"
require_relative "../packing_cache"

module Kompo
  # Section to compile the final binary.
  # Switches implementation based on the current platform.
  # Uses CollectDependencies's exported values for dependencies.
  class Packing < Taski::Section
    interfaces :output_path

    def impl
      macos? ? ForMacOS : ForLinux
    end

    # Common helper methods shared between macOS and Linux implementations
    module CommonHelpers
      private

      # Cache-aware packing info retrieval
      # Returns hash with ALL info needed for final binary compilation
      def get_packing_info(work_dir, deps, ext_paths, enc_files)
        return @packing_info if @packing_info

        cache = build_packing_cache(work_dir, deps.ruby_version)

        if cache&.exists? && !Taski.args[:no_cache]
          puts "Restoring packing info from cache"
          @packing_info = cache.restore(work_dir, deps.ruby_build_path)
        else
          @packing_info = extract_packing_info(work_dir, deps, ext_paths, enc_files)
          save_to_packing_cache(work_dir, deps, @packing_info) unless Taski.args[:no_cache]
        end

        @packing_info
      end

      def extract_packing_info(work_dir, deps, ext_paths, enc_files)
        {
          # From Makefiles
          ldflags: get_ldflags(work_dir, deps.ruby_major_minor),
          libpath: get_libpath(work_dir, deps.ruby_major_minor),
          gem_libs: get_gem_libs(work_dir, deps.ruby_major_minor),
          extlibs: get_extlibs(deps.ruby_build_path, deps.ruby_version),
          # From pkg-config
          main_libs: get_ruby_mainlibs(deps.ruby_install_dir),
          ruby_cflags: get_ruby_cflags(deps.ruby_install_dir),
          # From InstallDeps
          static_libs: deps.static_libs,
          deps_lib_paths: deps.deps_lib_paths,
          # Ruby paths
          ruby_lib: deps.ruby_lib,
          ruby_build_path: deps.ruby_build_path,
          ruby_install_dir: deps.ruby_install_dir,
          ruby_version: deps.ruby_version,
          ruby_major_minor: deps.ruby_major_minor,
          # Other
          kompo_lib: deps.kompo_lib,
          ext_paths: ext_paths,
          enc_files: enc_files
        }
      end

      def build_packing_cache(work_dir, ruby_version)
        cache_dir = Taski.args.fetch(:cache_dir, DEFAULT_CACHE_DIR)
        PackingCache.from_work_dir(cache_dir: cache_dir, ruby_version: ruby_version, work_dir: work_dir)
      end

      def save_to_packing_cache(work_dir, deps, info)
        cache = build_packing_cache(work_dir, deps.ruby_version)
        return unless cache

        cache.save(work_dir, deps.ruby_build_path, info)
        puts "Saved packing info to cache: #{cache.cache_dir}"
      end

      def get_ruby_cflags(ruby_install_dir)
        ruby_pc = File.join(ruby_install_dir, "lib", "pkgconfig", "ruby.pc")
        result = Kompo.command_runner.capture("pkg-config", "--cflags", ruby_pc, suppress_stderr: true)
        Shellwords.split(result.chomp)
      end

      def get_ruby_mainlibs(ruby_install_dir)
        ruby_pc = File.join(ruby_install_dir, "lib", "pkgconfig", "ruby.pc")
        result = Kompo.command_runner.capture("pkg-config", "--variable=MAINLIBS", ruby_pc, suppress_stderr: true)
        result.chomp
      end

      def get_ldflags(work_dir, ruby_major_minor)
        makefiles = Dir.glob("#{work_dir}/bundle/ruby/#{ruby_major_minor}.0/gems/*/ext/*/Makefile")
        flags = makefiles.flat_map do |makefile|
          content = File.read(makefile)
          ldflags = content.scan(/^ldflags\s+= (.*)/).flatten
          ldflags += content.scan(/^LDFLAGS\s+= (.*)/).flatten
          ldflags.flat_map { |f| f.split(" ") }
        end
        flags.uniq.select { |f| f.start_with?("-L") }
      end

      def get_libpath(work_dir, ruby_major_minor)
        makefiles = Dir.glob("#{work_dir}/bundle/ruby/#{ruby_major_minor}.0/gems/*/ext/*/Makefile")
        makefiles.flat_map do |makefile|
          content = File.read(makefile)
          content.scan(/^LIBPATH = (.*)/).flatten
        end.compact.flat_map { |p| p.split(" ") }.uniq
          .reject { |p| p.start_with?("-Wl,-rpath,") || !p.start_with?("-L/") }
      end

      def get_extlibs(ruby_build_path, ruby_version)
        ruby_build_dir = File.join(ruby_build_path, "ruby-#{ruby_version}")

        # Extract LIBS from ext/*/Makefile and .bundle/gems/*/ext/*/Makefile
        makefiles = Dir.glob(File.join(ruby_build_dir, "{ext/*,.bundle/gems/*/ext/*}", "Makefile"))
        makefiles.flat_map do |file|
          # Read file, collapse line continuations, then match both "LIBS =" and "LIBS +="
          content = File.read(file).gsub("\\\n", " ")
          content.scan(/^LIBS\s*\+?=\s*(.*)/).flatten
        end.compact.flat_map { |l| l.split }.uniq
      end

      def get_gem_libs(work_dir, ruby_major_minor)
        makefiles = Dir.glob("#{work_dir}/bundle/ruby/#{ruby_major_minor}.0/gems/*/ext/*/Makefile")
        makefiles.flat_map do |makefile|
          File.read(makefile).scan(/^LIBS = (.*)/).flatten
        end.compact.flat_map { |l| l.split(" ") }.uniq
          .map { |l| l.start_with?("-l") ? l : "-l#{File.basename(l, ".a").delete_prefix("lib")}" }
      end
    end

    # macOS implementation - compiles with clang and Homebrew paths
    class ForMacOS < Taski::Task
      include CommonHelpers

      # macOS system libraries (always dynamically linked)
      SYSTEM_LIBS = %w[pthread m c].freeze
      # macOS frameworks
      FRAMEWORKS = %w[Foundation CoreFoundation Security].freeze

      def run
        work_dir = CollectDependencies.work_dir
        deps = CollectDependencies.deps
        ext_paths = CollectDependencies.ext_paths
        enc_files = CollectDependencies.enc_files
        @output_path = CollectDependencies.output_path

        # Get packing info from cache or extract from Makefiles
        packing = get_packing_info(work_dir, deps, ext_paths, enc_files)

        # fs.c is always regenerated (not from cache)
        command = build_command(deps, packing)

        if Taski.args[:dry_run]
          Taski.message(Shellwords.join(command))
          return
        end

        group("Compiling binary (macOS)") do
          Kompo.command_runner.run(*command, error_message: "Failed to compile final binary")
          puts "Binary size: #{File.size(@output_path) / 1024 / 1024} MB"
        end

        puts "Successfully created: #{@output_path}"
      end

      private

      def build_command(deps, packing)
        ruby_static_lib = "-lruby.#{packing[:ruby_major_minor]}-static"

        [
          "clang",
          "-O3",
          packing[:ruby_cflags],
          # IMPORTANT: kompo_lib must come FIRST to override Homebrew-installed versions
          "-L#{packing[:kompo_lib]}",
          packing[:ldflags],
          "-L#{packing[:ruby_lib]}",
          # Also add build path for static library lookup
          "-L#{File.join(packing[:ruby_build_path], "ruby-#{packing[:ruby_version]}")}",
          # Add library paths for dependencies (Homebrew on macOS)
          Shellwords.split(packing[:deps_lib_paths]),
          packing[:libpath],
          "-fstack-protector-strong",
          "-Wl,-dead_strip", # Remove unused code/data
          "-Wl,-no_deduplicate",  # Allow duplicate symbols from Ruby YJIT and kompo-vfs
          "-Wl,-export_dynamic",  # Export symbols to dynamic symbol table
          deps.main_c,  # Always fresh (regenerated each build)
          deps.fs_c,    # Always fresh (regenerated each build)
          # Link kompo_wrap FIRST (before Ruby) to override libc symbols
          "-lkompo_wrap",
          packing[:ext_paths],
          packing[:enc_files],
          ruby_static_lib,
          get_libs(packing),
          "-o", @output_path
        ].flatten
      end

      def get_libs(packing)
        main_libs = packing[:main_libs]
        gem_libs = packing[:gem_libs]
        ruby_std_gem_libs = packing[:extlibs]
        static_libs = packing[:static_libs]

        all_libs = [main_libs.split(" "), gem_libs, ruby_std_gem_libs].flatten
          .select { |l| l.match?(/-l\w/) }.uniq
          .reject { |l| l == "-ldl" } # macOS doesn't have libdl

        # Separate system libs from other libs
        other_libs = all_libs.reject { |l| SYSTEM_LIBS.any? { |sys| l == "-l#{sys}" } }

        # Build a lookup table from -l<name> flag to static library full path
        # e.g., {"-lgmp" => "/opt/homebrew/opt/gmp/lib/libgmp.a", ...}
        static_lib_map = build_static_lib_map(static_libs)

        # Get list of libraries that should remain dynamically linked
        dynamic_libs = Taski.args.fetch(:dynamic_libs, [])
        dynamic_lib_flags = dynamic_libs.map { |name| "-l#{name}" }

        # Replace dynamic library flags with static library paths where available
        # Skip static linking for libraries specified in --dynamic-libs option
        resolved_libs = other_libs.map do |lib_flag|
          # Keep as dynamic if specified in --dynamic-libs
          next lib_flag if dynamic_lib_flags.include?(lib_flag)

          static_lib_map[lib_flag] || lib_flag
        end

        [
          resolved_libs,
          "-lkompo_fs",
          # System libraries
          SYSTEM_LIBS.map { |l| "-l#{l}" },
          # Frameworks
          FRAMEWORKS.flat_map { |f| ["-framework", f] }
        ].flatten
      end

      # Build a map from -l<name> flag to static library full path
      # e.g., {"-lgmp" => "/opt/homebrew/opt/gmp/lib/libgmp.a", ...}
      # Automatically derives the flag from the library filename (lib<name>.a -> -l<name>)
      def build_static_lib_map(static_libs)
        return {} if static_libs.nil? || static_libs.empty?

        static_libs.to_h do |path|
          basename = File.basename(path, ".a") # "libgmp.a" -> "libgmp"
          lib_name = basename.delete_prefix("lib") # "libgmp" -> "gmp"
          ["-l#{lib_name}", path]
        end
      end
    end

    # Linux implementation - compiles with gcc and pkg-config paths
    class ForLinux < Taski::Task
      include CommonHelpers

      # Libraries that must be dynamically linked
      DYN_LINK_LIBS = %w[pthread dl m c].freeze

      def run
        work_dir = CollectDependencies.work_dir
        deps = CollectDependencies.deps
        ext_paths = CollectDependencies.ext_paths
        enc_files = CollectDependencies.enc_files
        @output_path = CollectDependencies.output_path

        # Get packing info from cache or extract from Makefiles
        packing = get_packing_info(work_dir, deps, ext_paths, enc_files)

        # fs.c is always regenerated (not from cache)
        command = build_command(deps, packing)

        if Taski.args[:dry_run]
          Taski.message(Shellwords.join(command))
          return
        end

        group("Compiling binary (Linux)") do
          Kompo.command_runner.run(*command, error_message: "Failed to compile final binary")
          puts "Binary size: #{File.size(@output_path) / 1024 / 1024} MB"
        end

        puts "Successfully created: #{@output_path}"
      end

      private

      def build_command(deps, packing)
        # Linux uses libruby-static.a (not libruby.X.Y-static.a like macOS)
        ruby_static_lib = "-lruby-static"

        [
          "gcc",
          "-O3",
          "-no-pie", # Required: Rust std lib is not built with PIC
          packing[:ruby_cflags],
          # IMPORTANT: kompo_lib must come FIRST to override system-installed versions
          "-L#{packing[:kompo_lib]}",
          packing[:ldflags],
          "-L#{packing[:ruby_lib]}",
          # Also add build path for static library lookup
          "-L#{File.join(packing[:ruby_build_path], "ruby-#{packing[:ruby_version]}")}",
          # Add library paths for dependencies (from pkg-config)
          Shellwords.split(packing[:deps_lib_paths]),
          packing[:libpath],
          "-fstack-protector-strong",
          "-rdynamic", "-Wl,-export-dynamic",
          deps.main_c,  # Always fresh (regenerated each build)
          deps.fs_c,    # Always fresh (regenerated each build)
          "-Wl,-Bstatic",
          "-Wl,--start-group",
          packing[:ext_paths],
          packing[:enc_files],
          ruby_static_lib,
          get_libs(packing),
          "-o", @output_path
        ].flatten
      end

      def get_libs(packing)
        main_libs = packing[:main_libs]
        gem_libs = packing[:gem_libs]
        ruby_std_gem_libs = packing[:extlibs]

        # System libraries that must always be dynamically linked
        system_dyn_libs = DYN_LINK_LIBS.map { |l| "-l#{l}" }

        # User-specified libraries to remain dynamically linked
        user_dynamic_libs = Taski.args.fetch(:dynamic_libs, [])
        user_dynamic_lib_flags = user_dynamic_libs.map { |name| "-l#{name}" }

        all_libs = [main_libs.split(" "), gem_libs, ruby_std_gem_libs].flatten
          .select { |l| l.match?(/-l\w/) }.uniq

        # Partition into static and dynamic
        # Dynamic: system libs + user-specified dynamic libs
        static_libs, dyn_libs = all_libs.partition do |l|
          !system_dyn_libs.include?(l) && !user_dynamic_lib_flags.include?(l)
        end

        dyn_libs << "-lc"
        dyn_libs.unshift("-Wl,-Bdynamic")

        [static_libs, "-Wl,--end-group", "-lkompo_fs", "-lkompo_wrap", dyn_libs].flatten
      end
    end

    private

    def macos?
      RUBY_PLATFORM.include?("darwin")
    end
  end
end
