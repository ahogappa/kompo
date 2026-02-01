# frozen_string_literal: true

require "fileutils"
require_relative "cache/base"
require_relative "cache/bundle"
require_relative "cache/packing"
require_relative "cache/native_extension"

module Kompo
  # Default cache directory
  DEFAULT_CACHE_DIR = File.expand_path("~/.kompo/cache")

  # Clean the cache for specified Ruby version
  # @param version [String] Ruby version to clean, or "all" to clean all caches
  # @param cache_dir [String] Cache directory path (default: ~/.kompo/cache)
  def self.clean_cache(version, cache_dir: DEFAULT_CACHE_DIR)
    unless Dir.exist?(cache_dir)
      puts "Cache directory does not exist: #{cache_dir}"
      return
    end

    if version == "all"
      clean_all_caches(cache_dir)
    else
      clean_version_cache(cache_dir, version)
    end
  end

  # Clean all caches in the cache directory
  def self.clean_all_caches(cache_dir)
    entries = Dir.glob(File.join(cache_dir, "*"))
    if entries.empty?
      puts "No caches found in #{cache_dir}"
      return
    end

    entries.each do |entry|
      FileUtils.rm_rf(entry)
      puts "Removed: #{entry}"
    end

    puts "All caches cleaned successfully"
  end
  private_class_method :clean_all_caches

  # Clean cache for a specific Ruby version
  # New structure: ~/.kompo/cache/{version}/ contains all caches for that version
  def self.clean_version_cache(cache_dir, version)
    version_cache_dir = File.join(cache_dir, version)

    unless Dir.exist?(version_cache_dir)
      puts "No cache found for Ruby #{version}"
      return
    end

    # Validate that version_cache_dir is under cache_dir to prevent path traversal
    real_cache_dir = File.realpath(cache_dir)
    real_version_cache = File.realpath(version_cache_dir)

    unless real_version_cache.start_with?(real_cache_dir + File::SEPARATOR) ||
        real_version_cache == real_cache_dir
      puts "Error: Invalid cache path detected (possible path traversal)"
      return
    end

    FileUtils.rm_rf(real_version_cache)
    puts "Removed: #{real_version_cache}"
    puts "Cache for Ruby #{version} cleaned successfully"
  end
  private_class_method :clean_version_cache
end
