# frozen_string_literal: true

require "open3"
require "shellwords"

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

      def get_ruby_cflags(ruby_install_dir)
        ruby_pc = File.join(ruby_install_dir, "lib", "pkgconfig", "ruby.pc")
        output, = Open3.capture2("pkg-config", "--cflags", ruby_pc, err: File::NULL)
        Shellwords.split(output.chomp)
      end

      def get_ruby_mainlibs(ruby_install_dir)
        ruby_pc = File.join(ruby_install_dir, "lib", "pkgconfig", "ruby.pc")
        output, = Open3.capture2("pkg-config", "--variable=MAINLIBS", ruby_pc, err: File::NULL)
        output.chomp
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

        command = build_command(work_dir, deps, ext_paths, enc_files)

        if Taski.args[:dry_run]
          Taski.message(Shellwords.join(command))
          return
        end

        group("Compiling binary (macOS)") do
          system(*command) or raise "Failed to compile final binary"
          puts "Binary size: #{File.size(@output_path) / 1024 / 1024} MB"
        end

        puts "Successfully created: #{@output_path}"
      end

      private

      def build_command(work_dir, deps, ext_paths, enc_files)
        ruby_static_lib = "-lruby.#{deps.ruby_major_minor}-static"

        [
          "clang",
          "-O3",
          get_ruby_cflags(deps.ruby_install_dir),
          # IMPORTANT: kompo_lib must come FIRST to override Homebrew-installed versions
          "-L#{deps.kompo_lib}",
          get_ldflags(work_dir, deps.ruby_major_minor),
          "-L#{deps.ruby_lib}",
          # Also add build path for static library lookup
          "-L#{File.join(deps.ruby_build_path, "ruby-#{deps.ruby_version}")}",
          # Add library paths for dependencies (Homebrew on macOS)
          Shellwords.split(deps.deps_lib_paths),
          get_libpath(work_dir, deps.ruby_major_minor),
          "-fstack-protector-strong",
          "-Wl,-dead_strip", # Remove unused code/data
          "-Wl,-no_deduplicate",  # Allow duplicate symbols from Ruby YJIT and kompo-vfs
          "-Wl,-export_dynamic",  # Export symbols to dynamic symbol table
          deps.main_c,
          deps.fs_c,
          # Link kompo_wrap FIRST (before Ruby) to override libc symbols
          "-lkompo_wrap",
          ext_paths,
          enc_files,
          ruby_static_lib,
          get_libs(deps.ruby_install_dir, work_dir, deps.ruby_build_path, deps.ruby_version, deps.ruby_major_minor, deps.static_libs),
          "-o", @output_path
        ].flatten
      end

      def get_libs(ruby_install_dir, work_dir, ruby_build_path, ruby_version, ruby_major_minor, static_libs)
        main_libs = get_ruby_mainlibs(ruby_install_dir)
        ruby_std_gem_libs = get_extlibs(ruby_build_path, ruby_version)
        gem_libs = get_gem_libs(work_dir, ruby_major_minor)

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

        command = build_command(work_dir, deps, ext_paths, enc_files)

        if Taski.args[:dry_run]
          Taski.message(Shellwords.join(command))
          return
        end

        group("Compiling binary (Linux)") do
          system(*command) or raise "Failed to compile final binary"
          puts "Binary size: #{File.size(@output_path) / 1024 / 1024} MB"
        end

        puts "Successfully created: #{@output_path}"
      end

      private

      def build_command(work_dir, deps, ext_paths, enc_files)
        # Linux uses libruby-static.a (not libruby.X.Y-static.a like macOS)
        ruby_static_lib = "-lruby-static"

        [
          "gcc",
          "-O3",
          "-no-pie", # Required: Rust std lib is not built with PIC
          get_ruby_cflags(deps.ruby_install_dir),
          # IMPORTANT: kompo_lib must come FIRST to override system-installed versions
          "-L#{deps.kompo_lib}",
          get_ldflags(work_dir, deps.ruby_major_minor),
          "-L#{deps.ruby_lib}",
          # Also add build path for static library lookup
          "-L#{File.join(deps.ruby_build_path, "ruby-#{deps.ruby_version}")}",
          # Add library paths for dependencies (from pkg-config)
          Shellwords.split(deps.deps_lib_paths),
          get_libpath(work_dir, deps.ruby_major_minor),
          "-fstack-protector-strong",
          "-rdynamic", "-Wl,-export-dynamic",
          deps.main_c,
          deps.fs_c,
          "-Wl,-Bstatic",
          "-Wl,--start-group",
          ext_paths,
          enc_files,
          ruby_static_lib,
          get_libs(deps.ruby_install_dir, work_dir, deps.ruby_build_path, deps.ruby_version, deps.ruby_major_minor),
          "-o", @output_path
        ].flatten
      end

      def get_libs(ruby_install_dir, work_dir, ruby_build_path, ruby_version, ruby_major_minor)
        main_libs = get_ruby_mainlibs(ruby_install_dir)
        ruby_std_gem_libs = get_extlibs(ruby_build_path, ruby_version)
        gem_libs = get_gem_libs(work_dir, ruby_major_minor)

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
