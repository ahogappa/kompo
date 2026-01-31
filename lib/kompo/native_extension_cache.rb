# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"

module Kompo
  # Manages native extension cache operations for BuildNativeGem
  # Handles cache existence checks, saving, and restoring of compiled extensions
  class NativeExtensionCache
    attr_reader :cache_dir

    # @param cache_dir [String] Base cache directory (e.g., ~/.kompo/cache)
    # @param ruby_version [String] Ruby version (e.g., "3.4.1")
    # @param gemfile_lock_hash [String] Hash of Gemfile.lock content
    def initialize(cache_dir:, ruby_version:, gemfile_lock_hash:)
      @base_cache_dir = cache_dir
      @ruby_version = ruby_version
      @hash = gemfile_lock_hash
      @cache_dir = File.join(@base_cache_dir, @ruby_version, "ext-#{@hash}")
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

    # Compute SHA256 hash of Gemfile.lock (first 16 chars)
    # @param work_dir [String] Directory containing Gemfile.lock
    # @return [String, nil] Hash string or nil if file not found
    def self.compute_gemfile_lock_hash(work_dir)
      gemfile_lock_path = File.join(work_dir, "Gemfile.lock")
      return nil unless File.exist?(gemfile_lock_path)

      content = File.read(gemfile_lock_path)
      Digest::SHA256.hexdigest(content)[0..15]
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

    # Read metadata from cache
    # @return [Hash, nil] Metadata hash or nil if not found
    def metadata
      return nil unless File.exist?(metadata_path)

      JSON.parse(File.read(metadata_path))
    end

    private

    def ext_dir
      File.join(@cache_dir, "ext")
    end

    def ports_cache_dir
      File.join(@cache_dir, "ports")
    end

    def metadata_path
      File.join(@cache_dir, "metadata.json")
    end

    # Save ports directories from gems to cache
    # These contain compiled native libraries like libxml2, libxslt
    def save_ports_directories(work_dir)
      gem_ports = Dir.glob(File.join(work_dir, "bundle/ruby/*/gems/*/ports"))
      return if gem_ports.empty?

      FileUtils.mkdir_p(ports_cache_dir)

      gem_ports.each do |port_path|
        gem_name = File.basename(File.dirname(port_path))
        dest = File.join(ports_cache_dir, gem_name)
        FileUtils.cp_r(port_path, dest)
      end
    end

    # Restore ports directories from cache to gems
    def restore_ports_directories(work_dir)
      return unless Dir.exist?(ports_cache_dir)

      Dir.glob(File.join(ports_cache_dir, "*")).each do |cached_gem_ports|
        gem_name = File.basename(cached_gem_ports)
        # Find the gem directory in work_dir
        gem_dir = Dir.glob(File.join(work_dir, "bundle/ruby/*/gems/#{gem_name}")).first
        next unless gem_dir

        dest = File.join(gem_dir, "ports")
        FileUtils.rm_rf(dest) if Dir.exist?(dest)
        FileUtils.cp_r(cached_gem_ports, dest)
      end
    end

    # List gem names that have ports directories
    def list_ports_directories(work_dir)
      Dir.glob(File.join(work_dir, "bundle/ruby/*/gems/*/ports"))
        .map { |p| File.basename(File.dirname(p)) }
    end
  end
end
