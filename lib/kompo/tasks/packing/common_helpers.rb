# frozen_string_literal: true

require "shellwords"

module Kompo
  class Packing < Taski::Task
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
