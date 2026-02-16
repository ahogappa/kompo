# frozen_string_literal: true

require "shellwords"

module Kompo
  class Packing < Taski::Task
    # macOS implementation - compiles with clang and Homebrew paths
    class ForMacOS < Taski::Task
      exports :output_path

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
  end
end
