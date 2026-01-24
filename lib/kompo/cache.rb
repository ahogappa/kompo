# frozen_string_literal: true

require 'fileutils'

module Kompo
  # Clean the cache for specified Ruby version
  # @param version [String] Ruby version to clean, or "all" to clean all caches
  def self.clean_cache(version)
    kompo_cache = File.expand_path('~/.kompo/cache')

    unless Dir.exist?(kompo_cache)
      puts "Cache directory does not exist: #{kompo_cache}"
      return
    end

    if version == 'all'
      clean_all_caches(kompo_cache)
    else
      clean_version_cache(kompo_cache, version)
    end
  end

  # Clean all caches in the cache directory
  def self.clean_all_caches(kompo_cache)
    entries = Dir.glob(File.join(kompo_cache, '*'))
    if entries.empty?
      puts "No caches found in #{kompo_cache}"
      return
    end

    entries.each do |entry|
      FileUtils.rm_rf(entry)
      puts "Removed: #{entry}"
    end

    puts 'All caches cleaned successfully'
  end
  private_class_method :clean_all_caches

  # Clean cache for a specific Ruby version
  # New structure: ~/.kompo/cache/{version}/ contains all caches for that version
  def self.clean_version_cache(kompo_cache, version)
    version_cache_dir = File.join(kompo_cache, version)

    unless Dir.exist?(version_cache_dir)
      puts "No cache found for Ruby #{version}"
      return
    end

    # Validate that version_cache_dir is under kompo_cache to prevent path traversal
    real_kompo_cache = File.realpath(kompo_cache)
    real_version_cache = File.realpath(version_cache_dir)

    unless real_version_cache.start_with?(real_kompo_cache + File::SEPARATOR) ||
           real_version_cache == real_kompo_cache
      puts 'Error: Invalid cache path detected (possible path traversal)'
      return
    end

    FileUtils.rm_rf(real_version_cache)
    puts "Removed: #{real_version_cache}"
    puts "Cache for Ruby #{version} cleaned successfully"
  end
  private_class_method :clean_version_cache
end
