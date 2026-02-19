# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/kompo/cache/bundle"

class BundleCacheTest < Minitest::Test
  def test_compute_gemfile_lock_hash_returns_hash
    with_tmpdir do |tmpdir|
      gemfile_lock_content = "GEM\n  specs:\n"
      tmpdir << ["Gemfile.lock", gemfile_lock_content]

      hash = Kompo::BundleCache.compute_gemfile_lock_hash(tmpdir)

      expected_hash = Digest::SHA256.hexdigest(gemfile_lock_content)[0..15]
      assert_equal expected_hash, hash
    end
  end

  def test_compute_gemfile_lock_hash_returns_nil_when_file_not_found
    with_tmpdir do |tmpdir|
      hash = Kompo::BundleCache.compute_gemfile_lock_hash(tmpdir)

      assert_nil hash
    end
  end

  def test_from_work_dir_creates_cache_instance
    with_tmpdir do |tmpdir|
      gemfile_lock_content = "GEM\n  specs:\n"
      tmpdir << ["Gemfile.lock", gemfile_lock_content]

      cache = Kompo::BundleCache.from_work_dir(
        cache_dir: "/tmp/cache",
        ruby_version: "3.4.1",
        work_dir: tmpdir
      )

      assert_instance_of Kompo::BundleCache, cache
      hash = Digest::SHA256.hexdigest(gemfile_lock_content)[0..15]
      assert_equal "/tmp/cache/3.4.1/bundle-#{hash}", cache.cache_dir
    end
  end

  def test_from_work_dir_returns_nil_when_no_gemfile_lock
    with_tmpdir do |tmpdir|
      cache = Kompo::BundleCache.from_work_dir(
        cache_dir: "/tmp/cache",
        ruby_version: "3.4.1",
        work_dir: tmpdir
      )

      assert_nil cache
    end
  end

  def test_cache_dir_is_correct
    cache = Kompo::BundleCache.new(
      cache_dir: "/tmp/cache",
      ruby_version: "3.4.1",
      gemfile_lock_hash: "abc123"
    )

    assert_equal "/tmp/cache/3.4.1/bundle-abc123", cache.cache_dir
  end

  def test_exists_returns_false_when_no_cache
    with_tmpdir do |tmpdir|
      cache = Kompo::BundleCache.new(
        cache_dir: tmpdir,
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      refute cache.exists?
    end
  end

  def test_exists_returns_false_when_partial_cache
    with_tmpdir do |tmpdir|
      cache = Kompo::BundleCache.new(
        cache_dir: tmpdir,
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      # Only create bundle directory (missing .bundle and metadata.json)
      FileUtils.mkdir_p(File.join(cache.cache_dir, "bundle"))

      refute cache.exists?
    end
  end

  def test_exists_returns_true_when_complete_cache
    with_tmpdir do |tmpdir|
      cache = Kompo::BundleCache.new(
        cache_dir: tmpdir,
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      # Create complete cache structure
      FileUtils.mkdir_p(File.join(cache.cache_dir, "bundle"))
      FileUtils.mkdir_p(File.join(cache.cache_dir, ".bundle"))
      File.write(File.join(cache.cache_dir, "metadata.json"), "{}")

      assert cache.exists?
    end
  end

  def test_save_creates_cache_structure
    with_tmpdir do |tmpdir|
      work_dir = tmpdir / "work"
      tmpdir << "work/bundle/ruby/3.4.0/" \
             << "work/.bundle/" \
             << ["work/.bundle/config", "BUNDLE_PATH: bundle"]

      cache = Kompo::BundleCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      cache.save(work_dir)

      assert cache.exists?
      assert Dir.exist?(File.join(cache.cache_dir, "bundle", "ruby", "3.4.0"))
      assert File.exist?(File.join(cache.cache_dir, ".bundle", "config"))
      assert File.exist?(File.join(cache.cache_dir, "metadata.json"))
    end
  end

  def test_save_creates_metadata_with_correct_content
    with_tmpdir do |tmpdir|
      work_dir = tmpdir / "work"
      tmpdir << "work/bundle/" << "work/.bundle/"

      cache = Kompo::BundleCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      cache.save(work_dir)

      metadata = cache.metadata
      assert_equal "3.4.1", metadata["ruby_version"]
      assert_equal "abc123", metadata["gemfile_lock_hash"]
      assert metadata["created_at"]
    end
  end

  def test_save_overwrites_existing_cache
    with_tmpdir do |tmpdir|
      work_dir = tmpdir / "work"
      tmpdir << "work/bundle/" \
             << ["work/.bundle/config", "NEW_CONFIG"]

      cache = Kompo::BundleCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      # Create old cache
      FileUtils.mkdir_p(File.join(cache.cache_dir, "bundle"))
      FileUtils.mkdir_p(File.join(cache.cache_dir, ".bundle"))
      File.write(File.join(cache.cache_dir, ".bundle", "config"), "OLD_CONFIG")
      File.write(File.join(cache.cache_dir, "metadata.json"), "{}")

      cache.save(work_dir)

      content = File.read(File.join(cache.cache_dir, ".bundle", "config"))
      assert_equal "NEW_CONFIG", content
    end
  end

  def test_restore_copies_cache_to_work_dir
    with_tmpdir do |tmpdir|
      cache = Kompo::BundleCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      # Create cache
      FileUtils.mkdir_p(File.join(cache.cache_dir, "bundle", "ruby", "3.4.0", "gems", "sinatra-4.0.0"))
      FileUtils.mkdir_p(File.join(cache.cache_dir, ".bundle"))
      File.write(File.join(cache.cache_dir, ".bundle", "config"), "BUNDLE_PATH: bundle")
      File.write(File.join(cache.cache_dir, "metadata.json"), "{}")

      # Restore to work directory
      work_dir = tmpdir / "work"
      tmpdir << "work/"

      cache.restore(work_dir)

      assert Dir.exist?(File.join(work_dir, "bundle", "ruby", "3.4.0", "gems", "sinatra-4.0.0"))
      assert File.exist?(File.join(work_dir, ".bundle", "config"))
    end
  end

  def test_restore_cleans_existing_files
    with_tmpdir do |tmpdir|
      cache = Kompo::BundleCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      # Create cache
      FileUtils.mkdir_p(File.join(cache.cache_dir, "bundle"))
      FileUtils.mkdir_p(File.join(cache.cache_dir, ".bundle"))
      File.write(File.join(cache.cache_dir, ".bundle", "config"), "CACHED_CONFIG")
      File.write(File.join(cache.cache_dir, "metadata.json"), "{}")

      # Create work directory with existing files
      work_dir = tmpdir / "work"
      tmpdir << "work/bundle/old/" \
             << ["work/.bundle/config", "OLD_CONFIG"]

      cache.restore(work_dir)

      # Old files should be replaced
      refute Dir.exist?(File.join(work_dir, "bundle", "old"))
      content = File.read(File.join(work_dir, ".bundle", "config"))
      assert_equal "CACHED_CONFIG", content
    end
  end

  def test_metadata_returns_nil_when_no_cache
    with_tmpdir do |tmpdir|
      cache = Kompo::BundleCache.new(
        cache_dir: tmpdir,
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      assert_nil cache.metadata
    end
  end

  def test_metadata_returns_parsed_json
    with_tmpdir do |tmpdir|
      cache = Kompo::BundleCache.new(
        cache_dir: tmpdir,
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      FileUtils.mkdir_p(cache.cache_dir)
      File.write(File.join(cache.cache_dir, "metadata.json"), '{"ruby_version": "3.4.1"}')

      metadata = cache.metadata
      assert_equal "3.4.1", metadata["ruby_version"]
    end
  end
end
