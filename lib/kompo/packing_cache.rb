# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"

module Kompo
  # Manages packing cache operations for Packing
  # Handles cache of linker-related information extracted from Makefiles
  # This avoids stale work_dir paths when using BundleCache
  class PackingCache
    attr_reader :cache_dir

    # @param cache_dir [String] Base cache directory (e.g., ~/.kompo/cache)
    # @param ruby_version [String] Ruby version (e.g., "3.4.1")
    # @param gemfile_lock_hash [String] Hash of Gemfile.lock content
    def initialize(cache_dir:, ruby_version:, gemfile_lock_hash:)
      @base_cache_dir = cache_dir
      @ruby_version = ruby_version
      @hash = gemfile_lock_hash
      @cache_dir = File.join(@base_cache_dir, @ruby_version, "packing-#{@hash}")
    end

    # Create PackingCache from work directory by computing Gemfile.lock hash
    # @param cache_dir [String] Base cache directory
    # @param ruby_version [String] Ruby version
    # @param work_dir [String] Work directory containing Gemfile.lock
    # @return [PackingCache, nil] PackingCache instance or nil if Gemfile.lock not found
    def self.from_work_dir(cache_dir:, ruby_version:, work_dir:)
      gemfile_lock_path = File.join(work_dir, "Gemfile.lock")
      return nil unless File.exist?(gemfile_lock_path)

      hash = Digest::SHA256.hexdigest(File.read(gemfile_lock_path))[0..15]
      new(cache_dir: cache_dir, ruby_version: ruby_version, gemfile_lock_hash: hash)
    end

    # Check if cache exists
    # @return [Boolean]
    def exists?
      File.exist?(metadata_path)
    end

    # Save ALL packing info needed for final binary compilation
    # @param work_dir [String] Current work directory
    # @param ruby_build_path [String] Ruby build path (for ext_paths, enc_files normalization)
    # @param data [Hash] All packing data with keys:
    #   - ldflags: -L flags from gem Makefiles (work_dir relative)
    #   - libpath: LIBPATH from gem Makefiles (work_dir relative)
    #   - gem_libs: -l flags from gem Makefiles
    #   - extlibs: LIBS from Ruby standard extension Makefiles
    #   - main_libs: Ruby MAINLIBS from pkg-config
    #   - ruby_cflags: Ruby CFLAGS from pkg-config
    #   - static_libs: Full paths to static libraries (Homebrew, etc.)
    #   - deps_lib_paths: Library paths from InstallDeps
    #   - ext_paths: .o file paths (mixed: work_dir and ruby_build_path relative)
    #   - enc_files: Encoding files (ruby_build_path relative)
    #   - ruby_lib: Ruby lib path
    #   - ruby_build_path: Ruby build path
    #   - ruby_install_dir: Ruby install dir
    #   - ruby_version: Ruby version
    #   - ruby_major_minor: Ruby major.minor
    #   - kompo_lib: kompo-vfs lib path
    def save(work_dir, ruby_build_path, data)
      FileUtils.rm_rf(@cache_dir) if Dir.exist?(@cache_dir)
      FileUtils.mkdir_p(@cache_dir)

      ruby_dir = File.join(work_dir, "_ruby")

      metadata = {
        "ruby_version" => @ruby_version,
        "gemfile_lock_hash" => @hash,
        "created_at" => Time.now.iso8601,
        # Paths that need work_dir normalization
        "ldflags" => convert_to_relative(data[:ldflags] || [], work_dir),
        "libpath" => convert_to_relative(data[:libpath] || [], work_dir),
        # .o paths need special handling (some in work_dir, some in ruby_build_path)
        "ext_paths" => normalize_ext_paths(data[:ext_paths] || [], work_dir, ruby_build_path),
        "enc_files" => normalize_enc_files(data[:enc_files] || [], ruby_build_path),
        # Library flags (no path normalization needed)
        "gem_libs" => data[:gem_libs] || [],
        "extlibs" => data[:extlibs] || [],
        "main_libs" => data[:main_libs] || "",
        # ruby_cflags may contain -I paths that reference _ruby dir
        "ruby_cflags" => normalize_ruby_cflags(data[:ruby_cflags] || [], ruby_dir),
        # External library paths (absolute, unchanged)
        "static_libs" => data[:static_libs] || [],
        "deps_lib_paths" => data[:deps_lib_paths] || "",
        "kompo_lib" => data[:kompo_lib] || "",
        # Ruby paths (normalized to be relative to _ruby)
        "ruby_lib" => normalize_ruby_path(data[:ruby_lib] || "", ruby_dir),
        "ruby_build_path" => normalize_ruby_path(data[:ruby_build_path] || "", ruby_dir),
        "ruby_install_dir" => normalize_ruby_path(data[:ruby_install_dir] || "", ruby_dir),
        "ruby_version_str" => data[:ruby_version] || "",
        "ruby_major_minor" => data[:ruby_major_minor] || ""
      }
      File.write(metadata_path, JSON.pretty_generate(metadata))
    end

    # Restore packing info, converting relative paths to absolute
    # @param work_dir [String] Current work directory
    # @param ruby_build_path [String] Ruby build path
    # @return [Hash, nil] Restored packing data or nil if cache doesn't exist
    def restore(work_dir, ruby_build_path)
      return nil unless exists?

      data = JSON.parse(File.read(metadata_path))
      ruby_dir = File.join(work_dir, "_ruby")

      {
        ldflags: convert_to_absolute(data["ldflags"] || [], work_dir),
        libpath: convert_to_absolute(data["libpath"] || [], work_dir),
        ext_paths: restore_ext_paths(data["ext_paths"] || [], work_dir, ruby_build_path),
        enc_files: restore_enc_files(data["enc_files"] || [], ruby_build_path),
        gem_libs: data["gem_libs"] || [],
        extlibs: data["extlibs"] || [],
        main_libs: data["main_libs"] || "",
        ruby_cflags: restore_ruby_cflags(data["ruby_cflags"] || [], ruby_dir),
        static_libs: data["static_libs"] || [],
        deps_lib_paths: data["deps_lib_paths"] || "",
        kompo_lib: data["kompo_lib"] || "",
        ruby_lib: restore_ruby_path(data["ruby_lib"] || "", ruby_dir),
        ruby_build_path: restore_ruby_path(data["ruby_build_path"] || "", ruby_dir),
        ruby_install_dir: restore_ruby_path(data["ruby_install_dir"] || "", ruby_dir),
        ruby_version: data["ruby_version_str"] || "",
        ruby_major_minor: data["ruby_major_minor"] || ""
      }
    end

    # Read metadata from cache
    # @return [Hash, nil] Metadata hash or nil if not found
    def metadata
      return nil unless File.exist?(metadata_path)

      JSON.parse(File.read(metadata_path))
    end

    private

    def metadata_path
      File.join(@cache_dir, "metadata.json")
    end

    # Convert absolute -L paths starting with work_dir to relative
    def convert_to_relative(paths, work_dir)
      paths.map do |path|
        if path.start_with?("-L#{work_dir}")
          "-L" + path[2..].sub(%r{^#{Regexp.escape(work_dir)}/?}, "")
        else
          path
        end
      end
    end

    # Convert relative -L paths to absolute
    def convert_to_absolute(paths, work_dir)
      paths.map do |path|
        if path.start_with?("-L") && !path.start_with?("-L/")
          "-L" + File.join(work_dir, path[2..])
        else
          path
        end
      end
    end

    # Normalize ext_paths: store with marker prefix to identify source
    # "work:" for work_dir relative, "ruby:" for ruby_build_path relative
    def normalize_ext_paths(paths, work_dir, ruby_build_path)
      paths.map do |path|
        if path.start_with?(work_dir)
          "work:" + path.sub(%r{^#{Regexp.escape(work_dir)}/?}, "")
        elsif path.start_with?(ruby_build_path)
          "ruby:" + path.sub(%r{^#{Regexp.escape(ruby_build_path)}/?}, "")
        else
          path # External path, keep as-is
        end
      end
    end

    def restore_ext_paths(paths, work_dir, ruby_build_path)
      paths.map do |path|
        if path.start_with?("work:")
          File.join(work_dir, path.sub(/^work:/, ""))
        elsif path.start_with?("ruby:")
          File.join(ruby_build_path, path.sub(/^ruby:/, ""))
        else
          path
        end
      end
    end

    # Normalize enc_files (always relative to ruby_build_path)
    def normalize_enc_files(paths, ruby_build_path)
      paths.map do |path|
        path.sub(%r{^#{Regexp.escape(ruby_build_path)}/?}, "")
      end
    end

    def restore_enc_files(paths, ruby_build_path)
      paths.map do |path|
        File.join(ruby_build_path, path)
      end
    end

    # Normalize a ruby path: if it contains /_ruby/, store relative from _ruby
    def normalize_ruby_path(path, ruby_dir)
      return "" if path.nil? || path.empty?

      if path.include?("/_ruby/")
        idx = path.index("/_ruby/")
        path[(idx + 1)..] # Keep from "_ruby/..."
      elsif path.start_with?(ruby_dir)
        path.sub(%r{^#{Regexp.escape(ruby_dir)}/?}, "_ruby/")
      else
        path
      end
    end

    # Restore a ruby path: if it starts with _ruby/, prepend work_dir
    def restore_ruby_path(path, ruby_dir)
      return "" if path.nil? || path.empty?

      if path.start_with?("_ruby/")
        File.join(File.dirname(ruby_dir), path)
      else
        path
      end
    end

    # Normalize -I paths in ruby_cflags that reference _ruby dir
    def normalize_ruby_cflags(flags, ruby_dir)
      flags.map do |flag|
        if flag.start_with?("-I") && flag.include?("/_ruby/")
          idx = flag.index("/_ruby/")
          "-I" + flag[(idx + 1)..] # Keep from "_ruby/..."
        elsif flag.start_with?("-I#{ruby_dir}")
          "-I_ruby/" + flag[(ruby_dir.length + 3)..] # -I + path after ruby_dir/
        else
          flag
        end
      end
    end

    # Restore -I paths in ruby_cflags
    def restore_ruby_cflags(flags, ruby_dir)
      flags.map do |flag|
        if flag.start_with?("-I_ruby/")
          "-I" + File.join(File.dirname(ruby_dir), flag[2..])
        else
          flag
        end
      end
    end
  end
end
