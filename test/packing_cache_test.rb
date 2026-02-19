# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/kompo/cache/packing"

class PackingCacheTest < Minitest::Test
  def test_cache_dir_is_correct
    cache = Kompo::PackingCache.new(
      cache_dir: "/tmp/cache",
      ruby_version: "3.4.1",
      gemfile_lock_hash: "abc123"
    )

    assert_equal "/tmp/cache/3.4.1/packing-abc123", cache.cache_dir
  end

  def test_from_work_dir_creates_cache_instance
    with_tmpdir do |tmpdir|
      gemfile_lock_content = "GEM\n  specs:\n"
      tmpdir << ["Gemfile.lock", gemfile_lock_content]

      cache = Kompo::PackingCache.from_work_dir(
        cache_dir: "/tmp/cache",
        ruby_version: "3.4.1",
        work_dir: tmpdir
      )

      assert_instance_of Kompo::PackingCache, cache
      hash = Digest::SHA256.hexdigest(gemfile_lock_content)[0..15]
      assert_equal "/tmp/cache/3.4.1/packing-#{hash}", cache.cache_dir
    end
  end

  def test_from_work_dir_returns_nil_when_no_gemfile_lock
    with_tmpdir do |tmpdir|
      cache = Kompo::PackingCache.from_work_dir(
        cache_dir: "/tmp/cache",
        ruby_version: "3.4.1",
        work_dir: tmpdir
      )

      assert_nil cache
    end
  end

  def test_exists_returns_false_when_no_cache
    with_tmpdir do |tmpdir|
      cache = Kompo::PackingCache.new(
        cache_dir: tmpdir,
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      refute cache.exists?
    end
  end

  def test_exists_returns_true_when_cache_exists
    with_tmpdir do |tmpdir|
      cache = Kompo::PackingCache.new(
        cache_dir: tmpdir,
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      FileUtils.mkdir_p(cache.cache_dir)
      File.write(File.join(cache.cache_dir, "metadata.json"), "{}")

      assert cache.exists?
    end
  end

  def test_save_and_restore_roundtrip
    with_tmpdir do |tmpdir|
      work_dir = tmpdir / "work"
      ruby_build_path = tmpdir / "ruby_build"

      cache = Kompo::PackingCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      original_data = {
        ldflags: ["-L#{work_dir}/bundle/ruby/3.4.0/gems/nokogiri/ports/lib", "-L/opt/homebrew/lib"],
        libpath: ["-L#{work_dir}/bundle/ruby/3.4.0/gems/nokogiri/ext/lib"],
        gem_libs: ["-lxml2", "-lz"],
        extlibs: ["-lssl", "-lcrypto"],
        main_libs: "-lpthread -ldl -lm",
        ruby_cflags: ["-I/usr/include", "-O3"],
        static_libs: ["/opt/homebrew/opt/gmp/lib/libgmp.a"],
        deps_lib_paths: "-L/opt/homebrew/lib",
        ext_paths: ["#{work_dir}/ext/nokogiri/nokogiri.o", "#{ruby_build_path}/ext/openssl/openssl.o"],
        enc_files: ["#{ruby_build_path}/enc/encinit.o"],
        ruby_lib: "/opt/ruby/lib",
        ruby_build_path: ruby_build_path,
        ruby_install_dir: "/opt/ruby",
        ruby_version: "3.4.1",
        ruby_major_minor: "3.4",
        kompo_lib: "/path/to/kompo-vfs/lib"
      }

      cache.save(work_dir, ruby_build_path, original_data)

      # Restore with different work_dir and ruby_build_path
      new_work_dir = tmpdir / "new_work"
      new_ruby_build_path = tmpdir / "new_ruby_build"
      restored = cache.restore(new_work_dir, new_ruby_build_path)

      # ldflags should have work_dir replaced
      assert_includes restored[:ldflags], "-L#{new_work_dir}/bundle/ruby/3.4.0/gems/nokogiri/ports/lib"
      # External paths should be preserved
      assert_includes restored[:ldflags], "-L/opt/homebrew/lib"

      # libpath should have work_dir replaced
      assert_includes restored[:libpath], "-L#{new_work_dir}/bundle/ruby/3.4.0/gems/nokogiri/ext/lib"

      # ext_paths should have paths replaced
      assert_includes restored[:ext_paths], "#{new_work_dir}/ext/nokogiri/nokogiri.o"
      assert_includes restored[:ext_paths], "#{new_ruby_build_path}/ext/openssl/openssl.o"

      # enc_files should have ruby_build_path replaced
      assert_includes restored[:enc_files], "#{new_ruby_build_path}/enc/encinit.o"

      # Library flags should be preserved
      assert_equal ["-lxml2", "-lz"], restored[:gem_libs]
      assert_equal ["-lssl", "-lcrypto"], restored[:extlibs]
      assert_equal "-lpthread -ldl -lm", restored[:main_libs]
      assert_equal ["-I/usr/include", "-O3"], restored[:ruby_cflags]

      # External library paths should be preserved
      assert_equal ["/opt/homebrew/opt/gmp/lib/libgmp.a"], restored[:static_libs]
      assert_equal "-L/opt/homebrew/lib", restored[:deps_lib_paths]
      assert_equal "/path/to/kompo-vfs/lib", restored[:kompo_lib]

      # Ruby paths should be preserved (they come from InstallRuby, not work_dir)
      assert_equal "/opt/ruby/lib", restored[:ruby_lib]
      assert_equal ruby_build_path.to_s, restored[:ruby_build_path]
      assert_equal "/opt/ruby", restored[:ruby_install_dir]
      assert_equal "3.4.1", restored[:ruby_version]
      assert_equal "3.4", restored[:ruby_major_minor]
    end
  end

  def test_external_paths_unchanged
    with_tmpdir do |tmpdir|
      cache = Kompo::PackingCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      data = {
        ldflags: ["-L/opt/homebrew/lib", "-L/usr/local/lib"],
        libpath: ["-L/opt/homebrew/opt/openssl/lib"],
        static_libs: ["/opt/homebrew/opt/gmp/lib/libgmp.a"],
        deps_lib_paths: "-L/opt/homebrew/lib"
      }

      cache.save(tmpdir / "work", tmpdir / "ruby_build", data)
      restored = cache.restore("/new/work/dir", "/new/ruby/build")

      # All external paths should be unchanged
      assert_equal ["-L/opt/homebrew/lib", "-L/usr/local/lib"], restored[:ldflags]
      assert_equal ["-L/opt/homebrew/opt/openssl/lib"], restored[:libpath]
      assert_equal ["/opt/homebrew/opt/gmp/lib/libgmp.a"], restored[:static_libs]
      assert_equal "-L/opt/homebrew/lib", restored[:deps_lib_paths]
    end
  end

  def test_static_libs_preserved
    with_tmpdir do |tmpdir|
      cache = Kompo::PackingCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      static_libs = [
        "/opt/homebrew/opt/gmp/lib/libgmp.a",
        "/opt/homebrew/opt/openssl@3/lib/libssl.a",
        "/opt/homebrew/opt/openssl@3/lib/libcrypto.a"
      ]

      cache.save("/work", "/ruby", {static_libs: static_libs})
      restored = cache.restore("/new/work", "/new/ruby")

      assert_equal static_libs, restored[:static_libs]
    end
  end

  def test_main_libs_preserved
    with_tmpdir do |tmpdir|
      cache = Kompo::PackingCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      main_libs = "-lpthread -ldl -lm -lc"

      cache.save("/work", "/ruby", {main_libs: main_libs})
      restored = cache.restore("/new/work", "/new/ruby")

      assert_equal main_libs, restored[:main_libs]
    end
  end

  def test_extlibs_preserved
    with_tmpdir do |tmpdir|
      cache = Kompo::PackingCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      extlibs = ["-lssl", "-lcrypto", "-lz"]

      cache.save("/work", "/ruby", {extlibs: extlibs})
      restored = cache.restore("/new/work", "/new/ruby")

      assert_equal extlibs, restored[:extlibs]
    end
  end

  def test_deps_lib_paths_preserved
    with_tmpdir do |tmpdir|
      cache = Kompo::PackingCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      deps_lib_paths = "-L/opt/homebrew/lib -L/usr/local/lib"

      cache.save("/work", "/ruby", {deps_lib_paths: deps_lib_paths})
      restored = cache.restore("/new/work", "/new/ruby")

      assert_equal deps_lib_paths, restored[:deps_lib_paths]
    end
  end

  def test_save_creates_metadata_with_correct_content
    with_tmpdir do |tmpdir|
      cache = Kompo::PackingCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      cache.save("/work", "/ruby", {gem_libs: ["-lxml2"]})

      metadata = cache.metadata
      assert_equal "3.4.1", metadata["ruby_version"]
      assert_equal "abc123", metadata["gemfile_lock_hash"]
      assert metadata["created_at"]
      assert_equal ["-lxml2"], metadata["gem_libs"]
    end
  end

  def test_save_overwrites_existing_cache
    with_tmpdir do |tmpdir|
      cache = Kompo::PackingCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      # Create old cache
      FileUtils.mkdir_p(cache.cache_dir)
      File.write(File.join(cache.cache_dir, "metadata.json"), '{"gem_libs": ["-lold"]}')

      # Save new cache
      cache.save("/work", "/ruby", {gem_libs: ["-lnew"]})

      metadata = cache.metadata
      assert_equal ["-lnew"], metadata["gem_libs"]
    end
  end

  def test_metadata_returns_nil_when_no_cache
    with_tmpdir do |tmpdir|
      cache = Kompo::PackingCache.new(
        cache_dir: tmpdir,
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      assert_nil cache.metadata
    end
  end

  def test_restore_returns_nil_when_no_cache
    with_tmpdir do |tmpdir|
      cache = Kompo::PackingCache.new(
        cache_dir: tmpdir,
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      assert_nil cache.restore("/work", "/ruby")
    end
  end

  def test_handles_empty_data
    with_tmpdir do |tmpdir|
      cache = Kompo::PackingCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      cache.save("/work", "/ruby", {})
      restored = cache.restore("/new/work", "/new/ruby")

      assert_equal [], restored[:ldflags]
      assert_equal [], restored[:libpath]
      assert_equal [], restored[:ext_paths]
      assert_equal [], restored[:enc_files]
      assert_equal [], restored[:gem_libs]
      assert_equal [], restored[:extlibs]
      assert_equal "", restored[:main_libs]
      assert_equal [], restored[:ruby_cflags]
      assert_equal [], restored[:static_libs]
      assert_equal "", restored[:deps_lib_paths]
      assert_equal "", restored[:kompo_lib]
    end
  end

  def test_ruby_cflags_normalization
    with_tmpdir do |tmpdir|
      work_dir = tmpdir / "work"
      ruby_build_path = work_dir / "_ruby/build"

      cache = Kompo::PackingCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      original_data = {
        ruby_cflags: [
          "-I#{work_dir}/_ruby/include/ruby-3.4.0",
          "-I#{work_dir}/_ruby/include/ruby-3.4.0/x86_64-darwin",
          "-I/usr/include",
          "-O3"
        ]
      }

      cache.save(work_dir, ruby_build_path, original_data)

      # Restore with different work_dir
      new_work_dir = tmpdir / "new_work"
      new_ruby_build_path = new_work_dir / "_ruby/build"
      restored = cache.restore(new_work_dir, new_ruby_build_path)

      # Ruby-related -I paths should be updated to new work_dir
      assert_includes restored[:ruby_cflags], "-I#{new_work_dir}/_ruby/include/ruby-3.4.0"
      assert_includes restored[:ruby_cflags], "-I#{new_work_dir}/_ruby/include/ruby-3.4.0/x86_64-darwin"
      # External paths should be preserved
      assert_includes restored[:ruby_cflags], "-I/usr/include"
      assert_includes restored[:ruby_cflags], "-O3"
    end
  end

  def test_ruby_paths_normalization
    with_tmpdir do |tmpdir|
      work_dir = tmpdir / "work"
      ruby_build_path = work_dir / "_ruby/build"

      cache = Kompo::PackingCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      original_data = {
        ruby_lib: "#{work_dir}/_ruby/lib",
        ruby_build_path: "#{work_dir}/_ruby/build",
        ruby_install_dir: "#{work_dir}/_ruby/install"
      }

      cache.save(work_dir, ruby_build_path, original_data)

      # Restore with different work_dir
      new_work_dir = tmpdir / "new_work"
      new_ruby_build_path = new_work_dir / "_ruby/build"
      restored = cache.restore(new_work_dir, new_ruby_build_path)

      # Ruby paths should be updated to new work_dir
      assert_equal "#{new_work_dir}/_ruby/lib", restored[:ruby_lib]
      assert_equal "#{new_work_dir}/_ruby/build", restored[:ruby_build_path]
      assert_equal "#{new_work_dir}/_ruby/install", restored[:ruby_install_dir]
    end
  end

  def test_external_ruby_paths_preserved
    with_tmpdir do |tmpdir|
      cache = Kompo::PackingCache.new(
        cache_dir: tmpdir / "cache",
        ruby_version: "3.4.1",
        gemfile_lock_hash: "abc123"
      )

      # External ruby paths (e.g., system ruby) should be preserved as-is
      original_data = {
        ruby_lib: "/opt/ruby/lib",
        ruby_build_path: "/opt/ruby/build",
        ruby_install_dir: "/opt/ruby"
      }

      cache.save("/work", "/ruby", original_data)
      restored = cache.restore("/new/work", "/new/ruby")

      # External paths should be unchanged
      assert_equal "/opt/ruby/lib", restored[:ruby_lib]
      assert_equal "/opt/ruby/build", restored[:ruby_build_path]
      assert_equal "/opt/ruby", restored[:ruby_install_dir]
    end
  end
end
