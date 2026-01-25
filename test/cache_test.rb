# frozen_string_literal: true

require_relative "test_helper"

class CacheTest < Minitest::Test
  def setup
    @original_home = ENV["HOME"]
    @temp_home = Dir.mktmpdir
    ENV["HOME"] = @temp_home
    @cache_dir = File.join(@temp_home, ".kompo", "cache")
  end

  def teardown
    ENV["HOME"] = @original_home
    FileUtils.rm_rf(@temp_home)
  end

  def test_clean_cache_no_directory
    assert_output(/Cache directory does not exist/) do
      Kompo.clean_cache("3.4.1")
    end
  end

  def test_clean_cache_specific_version
    # New structure: ~/.kompo/cache/{version}/
    version_dir = File.join(@cache_dir, "3.4.1")
    FileUtils.mkdir_p(File.join(version_dir, "ruby"))
    File.write(File.join(version_dir, "metadata.json"), "{}")
    File.write(File.join(version_dir, "ruby-3.4.1.tar.gz"), "dummy tarball")

    # Clean specific version
    assert_output(/Removed.*3\.4\.1.*Cache for Ruby 3\.4\.1 cleaned successfully/m) do
      Kompo.clean_cache("3.4.1")
    end

    refute Dir.exist?(version_dir)
  end

  def test_clean_cache_specific_version_removes_all_contents
    # New structure: everything is under ~/.kompo/cache/{version}/
    version_dir = File.join(@cache_dir, "3.4.1")
    FileUtils.mkdir_p(File.join(version_dir, "ruby"))
    File.write(File.join(version_dir, "metadata.json"), "{}")
    File.write(File.join(version_dir, "ruby-3.4.1.tar.gz"), "dummy tarball")

    # Bundle caches are also under the version directory
    bundle_cache_dir = File.join(version_dir, "bundle-abc123def456")
    FileUtils.mkdir_p(File.join(bundle_cache_dir, "bundle"))
    FileUtils.mkdir_p(File.join(bundle_cache_dir, ".bundle"))
    File.write(File.join(bundle_cache_dir, "metadata.json"), "{}")

    bundle_cache_dir2 = File.join(version_dir, "bundle-xyz789")
    FileUtils.mkdir_p(File.join(bundle_cache_dir2, "bundle"))

    # Clean specific version - removes entire version directory
    assert_output(/Removed.*3\.4\.1.*Cache for Ruby 3\.4\.1 cleaned successfully/m) do
      Kompo.clean_cache("3.4.1")
    end

    refute Dir.exist?(version_dir)
  end

  def test_clean_cache_specific_version_does_not_remove_other_version
    # Create version 3.4.1 cache
    version_341 = File.join(@cache_dir, "3.4.1")
    FileUtils.mkdir_p(File.join(version_341, "ruby"))
    FileUtils.mkdir_p(File.join(version_341, "bundle-abc123"))

    # Create version 4.0.0 cache
    version_400 = File.join(@cache_dir, "4.0.0")
    FileUtils.mkdir_p(File.join(version_400, "ruby"))
    FileUtils.mkdir_p(File.join(version_400, "bundle-xyz789"))

    # Clean only 3.4.1
    Kompo.clean_cache("3.4.1")

    # 3.4.1 should be removed
    refute Dir.exist?(version_341)
    # 4.0.0 should still exist
    assert Dir.exist?(version_400)
  end

  def test_clean_cache_version_not_found
    FileUtils.mkdir_p(@cache_dir)

    assert_output(/No cache found for Ruby 3\.4\.1/) do
      Kompo.clean_cache("3.4.1")
    end
  end

  def test_clean_cache_all
    # Create multiple version caches
    FileUtils.mkdir_p(File.join(@cache_dir, "3.4.1", "ruby"))
    FileUtils.mkdir_p(File.join(@cache_dir, "4.0.0", "ruby"))

    # Clean all
    assert_output(/All caches cleaned successfully/) do
      Kompo.clean_cache("all")
    end

    assert_empty Dir.glob(File.join(@cache_dir, "*"))
  end

  def test_clean_cache_all_empty
    FileUtils.mkdir_p(@cache_dir)

    assert_output(/No caches found/) do
      Kompo.clean_cache("all")
    end
  end
end
