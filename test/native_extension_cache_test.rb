# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/kompo/native_extension_cache"

class NativeExtensionCacheTest < Minitest::Test
  def test_compute_gemfile_lock_hash_returns_hash
    Dir.mktmpdir do |tmpdir|
      gemfile_lock_content = "GEM\n  specs:\n"
      File.write(File.join(tmpdir, "Gemfile.lock"), gemfile_lock_content)

      hash = Kompo::NativeExtensionCache.compute_gemfile_lock_hash(tmpdir)

      expected_hash = Digest::SHA256.hexdigest(gemfile_lock_content)[0..15]
      assert_equal expected_hash, hash
    end
  end

  def test_compute_gemfile_lock_hash_returns_nil_when_file_not_found
    Dir.mktmpdir do |tmpdir|
      hash = Kompo::NativeExtensionCache.compute_gemfile_lock_hash(tmpdir)

      assert_nil hash
    end
  end

  def test_from_work_dir_creates_cache_instance
    Dir.mktmpdir do |tmpdir|
      gemfile_lock_content = "GEM\n  specs:\n"
      File.write(File.join(tmpdir, "Gemfile.lock"), gemfile_lock_content)

      cache = Kompo::NativeExtensionCache.from_work_dir(
        cache_dir: "/tmp/cache",
        ruby_version: "3.4.1",
        work_dir: tmpdir
      )

      assert_instance_of Kompo::NativeExtensionCache, cache
      hash = Digest::SHA256.hexdigest(gemfile_lock_content)[0..15]
      assert_equal "/tmp/cache/3.4.1/ext-#{hash}", cache.cache_dir
    end
  end

  def test_from_work_dir_returns_nil_when_no_gemfile_lock
    Dir.mktmpdir do |tmpdir|
      cache = Kompo::NativeExtensionCache.from_work_dir(
        cache_dir: "/tmp/cache",
        ruby_version: "3.4.1",
        work_dir: tmpdir
      )

      assert_nil cache
    end
  end

  def test_cache_dir_is_correct
    cache = Kompo::NativeExtensionCache.new(
      cache_dir: "/tmp/cache",
      ruby_version: "3.4.1",
      gemfile_lock_hash: "abc123"
    )

    assert_equal "/tmp/cache/3.4.1/ext-abc123", cache.cache_dir
  end

  def test_exists_returns_false_when_no_cache
    Dir.mktmpdir do |tmpdir|
      cache = Kompo::NativeExtensionCache.new(
        cache_dir: tmpdir,
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      refute cache.exists?
    end
  end

  def test_exists_returns_false_when_partial_cache
    Dir.mktmpdir do |tmpdir|
      cache = Kompo::NativeExtensionCache.new(
        cache_dir: tmpdir,
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      # Only create ext directory (missing metadata.json)
      FileUtils.mkdir_p(File.join(cache.cache_dir, "ext"))

      refute cache.exists?
    end
  end

  def test_exists_returns_true_when_complete_cache
    Dir.mktmpdir do |tmpdir|
      cache = Kompo::NativeExtensionCache.new(
        cache_dir: tmpdir,
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      # Create complete cache structure
      FileUtils.mkdir_p(File.join(cache.cache_dir, "ext"))
      File.write(File.join(cache.cache_dir, "metadata.json"), "{}")

      assert cache.exists?
    end
  end

  def test_save_creates_cache_structure
    Dir.mktmpdir do |tmpdir|
      tmpdir = File.realpath(tmpdir)

      work_dir = File.join(tmpdir, "work")
      FileUtils.mkdir_p(File.join(work_dir, "ext", "nokogiri"))
      File.write(File.join(work_dir, "ext", "nokogiri", "nokogiri.o"), "object file content")

      cache = Kompo::NativeExtensionCache.new(
        cache_dir: File.join(tmpdir, "cache"),
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      exts = [["nokogiri", "Init_nokogiri"]]
      cache.save(work_dir, exts)

      assert cache.exists?
      assert Dir.exist?(File.join(cache.cache_dir, "ext", "nokogiri"))
      assert File.exist?(File.join(cache.cache_dir, "ext", "nokogiri", "nokogiri.o"))
      assert File.exist?(File.join(cache.cache_dir, "metadata.json"))
    end
  end

  def test_save_creates_metadata_with_correct_content
    Dir.mktmpdir do |tmpdir|
      tmpdir = File.realpath(tmpdir)

      work_dir = File.join(tmpdir, "work")
      FileUtils.mkdir_p(File.join(work_dir, "ext"))

      cache = Kompo::NativeExtensionCache.new(
        cache_dir: File.join(tmpdir, "cache"),
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      exts = [["nokogiri", "Init_nokogiri"], ["oj", "Init_oj"]]
      cache.save(work_dir, exts)

      metadata = cache.metadata
      assert_equal "3.4.1", metadata["ruby_version"]
      assert_equal "abc123", metadata["gemfile_lock_hash"]
      assert metadata["created_at"]
      assert_equal exts, metadata["exts"]
    end
  end

  def test_save_does_nothing_when_no_ext_dir
    Dir.mktmpdir do |tmpdir|
      tmpdir = File.realpath(tmpdir)

      work_dir = File.join(tmpdir, "work")
      FileUtils.mkdir_p(work_dir)
      # No ext/ directory

      cache = Kompo::NativeExtensionCache.new(
        cache_dir: File.join(tmpdir, "cache"),
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      cache.save(work_dir, [])

      refute cache.exists?
    end
  end

  def test_save_overwrites_existing_cache
    Dir.mktmpdir do |tmpdir|
      tmpdir = File.realpath(tmpdir)

      work_dir = File.join(tmpdir, "work")
      FileUtils.mkdir_p(File.join(work_dir, "ext", "new_gem"))
      File.write(File.join(work_dir, "ext", "new_gem", "new.o"), "new content")

      cache = Kompo::NativeExtensionCache.new(
        cache_dir: File.join(tmpdir, "cache"),
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      # Create old cache
      FileUtils.mkdir_p(File.join(cache.cache_dir, "ext", "old_gem"))
      File.write(File.join(cache.cache_dir, "ext", "old_gem", "old.o"), "old content")
      File.write(File.join(cache.cache_dir, "metadata.json"), '{"exts": []}')

      new_exts = [["new_gem", "Init_new_gem"]]
      cache.save(work_dir, new_exts)

      # Old files should be gone
      refute Dir.exist?(File.join(cache.cache_dir, "ext", "old_gem"))
      # New files should exist
      assert Dir.exist?(File.join(cache.cache_dir, "ext", "new_gem"))
      assert_equal new_exts, cache.metadata["exts"]
    end
  end

  def test_restore_copies_cache_to_work_dir
    Dir.mktmpdir do |tmpdir|
      tmpdir = File.realpath(tmpdir)

      cache = Kompo::NativeExtensionCache.new(
        cache_dir: File.join(tmpdir, "cache"),
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      # Create cache
      FileUtils.mkdir_p(File.join(cache.cache_dir, "ext", "nokogiri"))
      File.write(File.join(cache.cache_dir, "ext", "nokogiri", "nokogiri.o"), "object file")
      exts = [["nokogiri", "Init_nokogiri"]]
      File.write(File.join(cache.cache_dir, "metadata.json"), JSON.generate({"exts" => exts}))

      # Restore to work directory
      work_dir = File.join(tmpdir, "work")
      FileUtils.mkdir_p(work_dir)

      restored_exts = cache.restore(work_dir)

      assert Dir.exist?(File.join(work_dir, "ext", "nokogiri"))
      assert File.exist?(File.join(work_dir, "ext", "nokogiri", "nokogiri.o"))
      assert_equal exts, restored_exts
    end
  end

  def test_restore_cleans_existing_files
    Dir.mktmpdir do |tmpdir|
      tmpdir = File.realpath(tmpdir)

      cache = Kompo::NativeExtensionCache.new(
        cache_dir: File.join(tmpdir, "cache"),
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      # Create cache
      FileUtils.mkdir_p(File.join(cache.cache_dir, "ext", "cached_gem"))
      File.write(File.join(cache.cache_dir, "ext", "cached_gem", "cached.o"), "cached content")
      File.write(File.join(cache.cache_dir, "metadata.json"), '{"exts": []}')

      # Create work directory with existing files
      work_dir = File.join(tmpdir, "work")
      FileUtils.mkdir_p(File.join(work_dir, "ext", "old_gem"))
      File.write(File.join(work_dir, "ext", "old_gem", "old.o"), "old content")

      cache.restore(work_dir)

      # Old files should be replaced
      refute Dir.exist?(File.join(work_dir, "ext", "old_gem"))
      assert Dir.exist?(File.join(work_dir, "ext", "cached_gem"))
    end
  end

  def test_metadata_returns_nil_when_no_cache
    Dir.mktmpdir do |tmpdir|
      cache = Kompo::NativeExtensionCache.new(
        cache_dir: tmpdir,
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      assert_nil cache.metadata
    end
  end

  def test_metadata_returns_parsed_json
    Dir.mktmpdir do |tmpdir|
      cache = Kompo::NativeExtensionCache.new(
        cache_dir: tmpdir,
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      FileUtils.mkdir_p(cache.cache_dir)
      File.write(
        File.join(cache.cache_dir, "metadata.json"),
        '{"ruby_version": "3.4.1", "exts": [["test", "Init_test"]]}'
      )

      metadata = cache.metadata
      assert_equal "3.4.1", metadata["ruby_version"]
      assert_equal [["test", "Init_test"]], metadata["exts"]
    end
  end
end
