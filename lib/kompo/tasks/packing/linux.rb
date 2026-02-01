# frozen_string_literal: true

require "shellwords"

module Kompo
  class Packing < Taski::Section
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
  end
end
