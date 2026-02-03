# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/kompo/cache/native_extension"

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

  def test_save_copies_ports_directories
    Dir.mktmpdir do |tmpdir|
      tmpdir = File.realpath(tmpdir)

      work_dir = File.join(tmpdir, "work")
      FileUtils.mkdir_p(File.join(work_dir, "ext", "nokogiri"))
      File.write(File.join(work_dir, "ext", "nokogiri", "nokogiri.o"), "object file content")

      # Create ports directory structure like nokogiri
      ports_dir = File.join(work_dir, "bundle/ruby/3.4.0/gems/nokogiri-1.19.0/ports/x86_64-darwin/libxml2/2.12.0/lib")
      FileUtils.mkdir_p(ports_dir)
      File.write(File.join(ports_dir, "libxml2.a"), "static lib content")

      cache = Kompo::NativeExtensionCache.new(
        cache_dir: File.join(tmpdir, "cache"),
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      exts = [["nokogiri", "Init_nokogiri"]]
      cache.save(work_dir, exts)

      # Verify ports directory was cached (relative path includes full path from gem)
      cached_ports = File.join(cache.cache_dir, "ports", "nokogiri-1.19.0/ports/x86_64-darwin/libxml2/2.12.0/lib/libxml2.a")
      assert File.exist?(cached_ports), "Ports directory should be cached"

      # Verify metadata includes ports info (relative path from gems directory)
      metadata = cache.metadata
      assert_includes metadata["ports"], "nokogiri-1.19.0/ports"
    end
  end

  def test_restore_copies_ports_directories_back
    Dir.mktmpdir do |tmpdir|
      tmpdir = File.realpath(tmpdir)

      cache = Kompo::NativeExtensionCache.new(
        cache_dir: File.join(tmpdir, "cache"),
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      # Create cached ext
      FileUtils.mkdir_p(File.join(cache.cache_dir, "ext", "nokogiri"))
      File.write(File.join(cache.cache_dir, "ext", "nokogiri", "nokogiri.o"), "object file")

      # Create cached ports (new structure: gem-name/ports/arch/lib/...)
      cached_ports_dir = File.join(cache.cache_dir, "ports/nokogiri-1.19.0/ports/x86_64-darwin/libxml2/2.12.0/lib")
      FileUtils.mkdir_p(cached_ports_dir)
      File.write(File.join(cached_ports_dir, "libxml2.a"), "static lib content")

      # Create metadata (relative path from gems directory)
      File.write(
        File.join(cache.cache_dir, "metadata.json"),
        JSON.generate({"exts" => [["nokogiri", "Init_nokogiri"]], "ports" => ["nokogiri-1.19.0/ports"]})
      )

      # Create work directory with bundle structure (simulating BundleCache restore)
      work_dir = File.join(tmpdir, "work")
      gem_dir = File.join(work_dir, "bundle/ruby/3.4.0/gems/nokogiri-1.19.0")
      FileUtils.mkdir_p(gem_dir)

      # Restore
      cache.restore(work_dir)

      # Verify ext was restored
      assert File.exist?(File.join(work_dir, "ext/nokogiri/nokogiri.o"))

      # Verify ports was restored to gem directory
      restored_ports = File.join(gem_dir, "ports/x86_64-darwin/libxml2/2.12.0/lib/libxml2.a")
      assert File.exist?(restored_ports), "Ports directory should be restored to gem directory"
    end
  end

  def test_restore_does_not_fail_when_no_ports_cache
    Dir.mktmpdir do |tmpdir|
      tmpdir = File.realpath(tmpdir)

      cache = Kompo::NativeExtensionCache.new(
        cache_dir: File.join(tmpdir, "cache"),
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      # Create cache without ports
      FileUtils.mkdir_p(File.join(cache.cache_dir, "ext", "simple_gem"))
      File.write(File.join(cache.cache_dir, "ext", "simple_gem", "simple.o"), "object file")
      File.write(File.join(cache.cache_dir, "metadata.json"), JSON.generate({"exts" => []}))

      work_dir = File.join(tmpdir, "work")
      FileUtils.mkdir_p(work_dir)

      # Should not raise
      cache.restore(work_dir)

      assert File.exist?(File.join(work_dir, "ext/simple_gem/simple.o"))
    end
  end

  def test_restore_skips_ports_for_missing_gems
    Dir.mktmpdir do |tmpdir|
      tmpdir = File.realpath(tmpdir)

      cache = Kompo::NativeExtensionCache.new(
        cache_dir: File.join(tmpdir, "cache"),
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      # Create cached ext and ports
      FileUtils.mkdir_p(File.join(cache.cache_dir, "ext", "nokogiri"))
      File.write(File.join(cache.cache_dir, "ext", "nokogiri", "nokogiri.o"), "object file")

      cached_ports_dir = File.join(cache.cache_dir, "ports/nokogiri-1.19.0/lib")
      FileUtils.mkdir_p(cached_ports_dir)
      File.write(File.join(cached_ports_dir, "libxml2.a"), "static lib")

      File.write(
        File.join(cache.cache_dir, "metadata.json"),
        JSON.generate({"exts" => [], "ports" => ["nokogiri-1.19.0"]})
      )

      # Create work directory WITHOUT the nokogiri gem
      work_dir = File.join(tmpdir, "work")
      FileUtils.mkdir_p(work_dir)

      # Should not raise even though gem directory doesn't exist
      cache.restore(work_dir)

      # ext should be restored
      assert File.exist?(File.join(work_dir, "ext/nokogiri/nokogiri.o"))
    end
  end

  def test_saves_and_restores_nested_ext_ports
    Dir.mktmpdir do |tmpdir|
      tmpdir = File.realpath(tmpdir)
      work_dir = File.join(tmpdir, "work")

      # Create nested ports (like nokogiri's libgumbo in ext/nokogiri/ports)
      nested_ports = File.join(work_dir, "bundle/ruby/3.4.0/gems/nokogiri-1.19.0/ext/nokogiri/ports/arm64-darwin/libgumbo/lib")
      FileUtils.mkdir_p(nested_ports)
      File.write(File.join(nested_ports, "libgumbo.a"), "fake lib")

      # Create ext directory
      ext_dir = File.join(work_dir, "ext/nokogiri")
      FileUtils.mkdir_p(ext_dir)
      File.write(File.join(ext_dir, "nokogiri.o"), "fake object")

      File.write(File.join(work_dir, "Gemfile.lock"), "GEM\n  specs:\n    nokogiri (1.19.0)\n")

      cache = Kompo::NativeExtensionCache.from_work_dir(
        cache_dir: File.join(tmpdir, "cache"),
        ruby_version: "3.4.1",
        work_dir: work_dir
      )

      cache.save(work_dir, [["nokogiri", "Init_nokogiri"]])

      # Restore to new work_dir
      new_work_dir = File.join(tmpdir, "new_work")
      FileUtils.mkdir_p(File.join(new_work_dir, "bundle/ruby/3.4.0/gems/nokogiri-1.19.0/ext/nokogiri"))

      cache.restore(new_work_dir)

      # Verify nested ports restored
      restored = File.join(new_work_dir, "bundle/ruby/3.4.0/gems/nokogiri-1.19.0/ext/nokogiri/ports/arm64-darwin/libgumbo/lib/libgumbo.a")
      assert File.exist?(restored), "Nested ext ports should be restored"
    end
  end
end
