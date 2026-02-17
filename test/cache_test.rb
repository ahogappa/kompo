# frozen_string_literal: true

require_relative "test_helper"

class CacheTest < Minitest::Test
  def test_clean_cache_no_directory
    with_tmpdir do |tmpdir|
      cache_dir = File.join(tmpdir, ".kompo", "cache")

      assert_output(/Cache directory does not exist/) do
        Kompo.clean_cache("3.4.1", cache_dir: cache_dir)
      end
    end
  end

  def test_clean_cache_specific_version
    with_tmpdir do |tmpdir|
      tmpdir << ".kompo/cache/3.4.1/ruby/" \
             << [".kompo/cache/3.4.1/metadata.json", "{}"] \
             << [".kompo/cache/3.4.1/ruby-3.4.1.tar.gz", "dummy tarball"]

      cache_dir = File.join(tmpdir, ".kompo", "cache")
      version_dir = File.join(cache_dir, "3.4.1")

      assert_output(/Removed.*3\.4\.1.*Cache for Ruby 3\.4\.1 cleaned successfully/m) do
        Kompo.clean_cache("3.4.1", cache_dir: cache_dir)
      end

      refute Dir.exist?(version_dir)
    end
  end

  def test_clean_cache_specific_version_removes_all_contents
    with_tmpdir do |tmpdir|
      tmpdir << ".kompo/cache/3.4.1/ruby/" \
             << [".kompo/cache/3.4.1/metadata.json", "{}"] \
             << [".kompo/cache/3.4.1/ruby-3.4.1.tar.gz", "dummy tarball"] \
             << ".kompo/cache/3.4.1/bundle-abc123def456/bundle/" \
             << ".kompo/cache/3.4.1/bundle-abc123def456/.bundle/" \
             << [".kompo/cache/3.4.1/bundle-abc123def456/metadata.json", "{}"] \
             << ".kompo/cache/3.4.1/bundle-xyz789/bundle/"

      cache_dir = File.join(tmpdir, ".kompo", "cache")
      version_dir = File.join(cache_dir, "3.4.1")

      assert_output(/Removed.*3\.4\.1.*Cache for Ruby 3\.4\.1 cleaned successfully/m) do
        Kompo.clean_cache("3.4.1", cache_dir: cache_dir)
      end

      refute Dir.exist?(version_dir)
    end
  end

  def test_clean_cache_specific_version_does_not_remove_other_version
    with_tmpdir do |tmpdir|
      # Create version 3.4.1 cache
      tmpdir << ".kompo/cache/3.4.1/ruby/" \
             << ".kompo/cache/3.4.1/bundle-abc123/"

      # Create version 4.0.0 cache
      tmpdir << ".kompo/cache/4.0.0/ruby/" \
             << ".kompo/cache/4.0.0/bundle-xyz789/"

      cache_dir = File.join(tmpdir, ".kompo", "cache")
      version_341 = File.join(cache_dir, "3.4.1")
      version_400 = File.join(cache_dir, "4.0.0")

      Kompo.clean_cache("3.4.1", cache_dir: cache_dir)

      # 3.4.1 should be removed
      refute Dir.exist?(version_341)
      # 4.0.0 should still exist
      assert Dir.exist?(version_400)
    end
  end

  def test_clean_cache_version_not_found
    with_tmpdir do |tmpdir|
      tmpdir << ".kompo/cache/"

      cache_dir = File.join(tmpdir, ".kompo", "cache")

      assert_output(/No cache found for Ruby 3\.4\.1/) do
        Kompo.clean_cache("3.4.1", cache_dir: cache_dir)
      end
    end
  end

  def test_clean_cache_all
    with_tmpdir do |tmpdir|
      # Create multiple version caches
      tmpdir << ".kompo/cache/3.4.1/ruby/" \
             << ".kompo/cache/4.0.0/ruby/"

      cache_dir = File.join(tmpdir, ".kompo", "cache")

      assert_output(/All caches cleaned successfully/) do
        Kompo.clean_cache("all", cache_dir: cache_dir)
      end

      assert_empty Dir.glob(File.join(cache_dir, "*"))
    end
  end

  def test_clean_cache_all_empty
    with_tmpdir do |tmpdir|
      tmpdir << ".kompo/cache/"

      cache_dir = File.join(tmpdir, ".kompo", "cache")

      assert_output(/No caches found/) do
        Kompo.clean_cache("all", cache_dir: cache_dir)
      end
    end
  end
end
