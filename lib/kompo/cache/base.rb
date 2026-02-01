# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"

module Kompo
  # Base class for all cache implementations
  # Provides common initialization and helper methods
  class CacheBase
    attr_reader :cache_dir

    # @param cache_dir [String] Base cache directory (e.g., ~/.kompo/cache)
    # @param ruby_version [String] Ruby version (e.g., "3.4.1")
    # @param gemfile_lock_hash [String] Hash of Gemfile.lock content
    # @param cache_prefix [String] Prefix for the cache subdirectory (e.g., "bundle", "packing", "ext")
    def initialize(cache_dir:, ruby_version:, gemfile_lock_hash:, cache_prefix:)
      @base_cache_dir = cache_dir
      @ruby_version = ruby_version
      @hash = gemfile_lock_hash
      @cache_dir = File.join(@base_cache_dir, @ruby_version, "#{cache_prefix}-#{@hash}")
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
  end
end
