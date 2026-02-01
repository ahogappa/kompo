# frozen_string_literal: true

require_relative "base"

module Kompo
  # Manages bundle cache operations for BundleInstall
  # Handles cache existence checks, saving, and restoring
  class BundleCache < CacheBase
    # @param cache_dir [String] Base cache directory (e.g., ~/.kompo/cache)
    # @param ruby_version [String] Ruby version (e.g., "3.4.1")
    # @param gemfile_lock_hash [String] Hash of Gemfile.lock content
    def initialize(cache_dir:, ruby_version:, gemfile_lock_hash:)
      super(cache_dir: cache_dir, ruby_version: ruby_version,
            gemfile_lock_hash: gemfile_lock_hash, cache_prefix: "bundle")
    end

    # Create BundleCache from work directory by computing Gemfile.lock hash
    # @param cache_dir [String] Base cache directory
    # @param ruby_version [String] Ruby version
    # @param work_dir [String] Work directory containing Gemfile.lock
    # @return [BundleCache, nil] BundleCache instance or nil if Gemfile.lock not found
    def self.from_work_dir(cache_dir:, ruby_version:, work_dir:)
      hash = compute_gemfile_lock_hash(work_dir)
      return nil unless hash

      new(cache_dir: cache_dir, ruby_version: ruby_version, gemfile_lock_hash: hash)
    end

    # Check if cache exists with all required files
    # @return [Boolean]
    def exists?
      Dir.exist?(bundle_dir) && Dir.exist?(bundle_config_dir) && File.exist?(metadata_path)
    end

    # Save bundle from work directory to cache
    # @param work_dir [String] Work directory containing bundle and .bundle
    def save(work_dir)
      # Remove old cache if exists
      FileUtils.rm_rf(@cache_dir) if Dir.exist?(@cache_dir)
      FileUtils.mkdir_p(@cache_dir)

      # Copy to cache
      FileUtils.cp_r(File.join(work_dir, "bundle"), bundle_dir)
      FileUtils.cp_r(File.join(work_dir, ".bundle"), bundle_config_dir)

      # Save metadata
      metadata = {
        "ruby_version" => @ruby_version,
        "gemfile_lock_hash" => @hash,
        "created_at" => Time.now.iso8601
      }
      File.write(metadata_path, JSON.pretty_generate(metadata))
    end

    # Restore bundle from cache to work directory
    # @param work_dir [String] Target work directory
    def restore(work_dir)
      # Clean up existing files in case work_dir is reused
      work_bundle_dir = File.join(work_dir, "bundle")
      work_bundle_config_dir = File.join(work_dir, ".bundle")

      FileUtils.rm_rf(work_bundle_dir) if Dir.exist?(work_bundle_dir)
      FileUtils.rm_rf(work_bundle_config_dir) if Dir.exist?(work_bundle_config_dir)

      # Copy from cache
      FileUtils.cp_r(bundle_dir, work_bundle_dir)
      FileUtils.cp_r(bundle_config_dir, work_bundle_config_dir)
    end

    private

    def bundle_dir
      File.join(@cache_dir, "bundle")
    end

    def bundle_config_dir
      File.join(@cache_dir, ".bundle")
    end
  end
end
