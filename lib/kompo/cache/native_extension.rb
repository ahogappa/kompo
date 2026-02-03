# frozen_string_literal: true

require_relative "base"

module Kompo
  # Manages native extension cache operations for BuildNativeGem
  # Handles cache existence checks, saving, and restoring of compiled extensions
  class NativeExtensionCache < CacheBase
    # @param cache_dir [String] Base cache directory (e.g., ~/.kompo/cache)
    # @param ruby_version [String] Ruby version (e.g., "3.4.1")
    # @param gemfile_lock_hash [String] Hash of Gemfile.lock content
    def initialize(cache_dir:, ruby_version:, gemfile_lock_hash:)
      super(cache_dir: cache_dir, ruby_version: ruby_version,
            gemfile_lock_hash: gemfile_lock_hash, cache_prefix: "ext")
    end

    # Create NativeExtensionCache from work directory by computing Gemfile.lock hash
    # @param cache_dir [String] Base cache directory
    # @param ruby_version [String] Ruby version
    # @param work_dir [String] Work directory containing Gemfile.lock
    # @return [NativeExtensionCache, nil] NativeExtensionCache instance or nil if Gemfile.lock not found
    def self.from_work_dir(cache_dir:, ruby_version:, work_dir:)
      hash = compute_gemfile_lock_hash(work_dir)
      return nil unless hash

      new(cache_dir: cache_dir, ruby_version: ruby_version, gemfile_lock_hash: hash)
    end

    # Check if cache exists with all required files
    # @return [Boolean]
    def exists?
      Dir.exist?(ext_dir) && File.exist?(metadata_path)
    end

    # Save ext directory from work directory to cache
    # @param work_dir [String] Work directory containing ext/
    # @param exts [Array] Array of [ext_path, init_func] pairs
    def save(work_dir, exts)
      work_ext_dir = File.join(work_dir, "ext")
      return unless Dir.exist?(work_ext_dir)

      # Remove old cache if exists
      FileUtils.rm_rf(@cache_dir) if Dir.exist?(@cache_dir)
      FileUtils.mkdir_p(@cache_dir)

      # Copy ext directory to cache
      FileUtils.cp_r(work_ext_dir, ext_dir)

      # Copy ports directories from gems (e.g., nokogiri's libxml2/libxslt)
      save_ports_directories(work_dir)

      # Save metadata including extension registration info
      metadata = {
        "ruby_version" => @ruby_version,
        "gemfile_lock_hash" => @hash,
        "created_at" => Time.now.iso8601,
        "exts" => exts,
        "ports" => list_ports_directories(work_dir)
      }
      File.write(metadata_path, JSON.pretty_generate(metadata))
    end

    # Restore ext directory from cache to work directory
    # @param work_dir [String] Target work directory
    # @return [Array] Array of [ext_path, init_func] pairs from cached metadata
    def restore(work_dir)
      work_ext_dir = File.join(work_dir, "ext")

      # Clean up existing ext directory
      FileUtils.rm_rf(work_ext_dir) if Dir.exist?(work_ext_dir)

      # Copy from cache
      FileUtils.cp_r(ext_dir, work_ext_dir)

      # Restore ports directories to gems
      restore_ports_directories(work_dir)

      # Return cached exts metadata
      metadata["exts"] || []
    end

    private

    def ext_dir
      File.join(@cache_dir, "ext")
    end

    def ports_cache_dir
      File.join(@cache_dir, "ports")
    end

    # Save ports directories from gems to cache
    # These contain compiled native libraries like libxml2, libxslt
    # Also handles nested ports directories (e.g., gems/*/ext/*/ports for libgumbo)
    def save_ports_directories(work_dir)
      # Find ALL ports directories including nested ones (gems/**/ports)
      all_ports = Dir.glob(File.join(work_dir, "bundle/ruby/*/gems/**/ports"))
      return if all_ports.empty?

      FileUtils.mkdir_p(ports_cache_dir)

      all_ports.each do |port_path|
        # Get path relative to gems directory
        relative = port_path.sub(%r{.*/bundle/ruby/[^/]+/gems/}, "")
        dest = File.join(ports_cache_dir, relative)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp_r(port_path, dest)
      end
    end

    # Restore ports directories from cache to gems
    # Handles both top-level and nested ports (e.g., gems/*/ext/*/ports)
    def restore_ports_directories(work_dir)
      return unless Dir.exist?(ports_cache_dir)

      # Find all cached ports directories
      Dir.glob(File.join(ports_cache_dir, "**/ports")).each do |cached_ports|
        # Get relative path from cache (e.g., "nokogiri-1.19.0/ext/nokogiri/ports")
        relative = cached_ports.sub("#{ports_cache_dir}/", "")
        # Remove trailing "/ports" to get parent path
        parent_relative = relative.sub(%r{/ports$}, "")

        # Find gem directory
        gem_name = parent_relative.split("/").first
        gem_dir = Dir.glob(File.join(work_dir, "bundle/ruby/*/gems/#{gem_name}")).first
        next unless gem_dir

        # Construct full destination path
        subpath = parent_relative.sub(%r{^[^/]+/?}, "") # Remove gem name
        dest_parent = subpath.empty? ? gem_dir : File.join(gem_dir, subpath)
        dest = File.join(dest_parent, "ports")

        FileUtils.rm_rf(dest) if Dir.exist?(dest)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp_r(cached_ports, dest)
      end
    end

    # List all ports directories (relative to gems directory)
    def list_ports_directories(work_dir)
      Dir.glob(File.join(work_dir, "bundle/ruby/*/gems/**/ports"))
        .map { |p| p.sub(%r{.*/bundle/ruby/[^/]+/gems/}, "") }
    end
  end
end
