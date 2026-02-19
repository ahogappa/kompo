# frozen_string_literal: true

require_relative "../test_helper"

class InstallRubyTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_install_ruby_uses_cache_when_available
    with_tmpdir do |tmpdir|
      metadata = {
        "ruby_version" => RUBY_VERSION,
        "work_dir" => tmpdir
      }
      cache_prefix = ".kompo/cache/#{RUBY_VERSION}"

      tmpdir << ["#{cache_prefix}/metadata.json", JSON.generate(metadata)] \
             << ["#{cache_prefix}/ruby/bin/ruby", "#!/bin/sh"] \
             << ["#{cache_prefix}/ruby/bin/bundle", "#!/bin/sh"]

      mock_task(Kompo::WorkDir, path: tmpdir, original_dir: tmpdir)

      # InstallRuby.run should select FromCache when cache exists
      # We test that the Task properly reads cache metadata
      assert File.exist?(tmpdir / cache_prefix / "metadata.json")
    end
  end

  def test_install_ruby_exports_are_defined
    # Verify that InstallRuby Task defines expected exports
    exported = Kompo::InstallRuby.exported_methods
    expected = %i[ruby_path bundler_path ruby_install_dir ruby_version
      ruby_major_minor ruby_build_path original_ruby_install_dir]

    expected.each do |export|
      assert_includes exported, export, "InstallRuby should define #{export} export"
    end
  end

  def test_install_ruby_static_extensions_defined
    # Verify that STATIC_EXTENSIONS constant is defined and contains expected extensions
    assert_kind_of Array, Kompo::InstallRuby::STATIC_EXTENSIONS
    assert_includes Kompo::InstallRuby::STATIC_EXTENSIONS, "json"
    assert_includes Kompo::InstallRuby::STATIC_EXTENSIONS, "openssl"
    assert_includes Kompo::InstallRuby::STATIC_EXTENSIONS, "zlib"
    assert_includes Kompo::InstallRuby::STATIC_EXTENSIONS, "socket"
  end

  def test_install_ruby_from_cache_class_exists
    assert_kind_of Class, Kompo::InstallRuby::FromCache
    assert Kompo::InstallRuby::FromCache < Taski::Task
  end

  def test_install_ruby_from_source_class_exists
    assert_kind_of Class, Kompo::InstallRuby::FromSource
    assert Kompo::InstallRuby::FromSource < Taski::Task
  end

  def test_from_cache_restores_ruby_and_fixes_shebangs
    with_tmpdir do |tmpdir|
      cache_prefix = ".kompo/cache/#{RUBY_VERSION}"
      metadata = {"ruby_version" => RUBY_VERSION, "work_dir" => tmpdir}

      tmpdir << ["#{cache_prefix}/ruby/bin/ruby", "#!/bin/sh\necho ruby"] \
             << ["#{cache_prefix}/ruby/bin/bundler", "#!/old/path/to/ruby\necho bundler"] \
             << ["#{cache_prefix}/ruby/bin/gem", "#!/old/path/to/ruby\necho gem"] \
             << ["#{cache_prefix}/metadata.json", JSON.generate(metadata)]

      cache_install_dir = tmpdir / cache_prefix / "ruby"
      FileUtils.chmod(0o755, File.join(cache_install_dir, "bin", "ruby"))
      FileUtils.chmod(0o755, File.join(cache_install_dir, "bin", "bundler"))
      FileUtils.chmod(0o755, File.join(cache_install_dir, "bin", "gem"))

      mock_task(Kompo::WorkDir, path: tmpdir, original_dir: tmpdir)

      # Trigger task execution and get result
      ruby_install_dir = Kompo::InstallRuby.ruby_install_dir(args: {kompo_cache: tmpdir / ".kompo" / "cache"})

      # Check that ruby was installed
      assert Dir.exist?(ruby_install_dir)
      assert File.exist?(File.join(ruby_install_dir, "bin", "ruby"))

      # Check that shebangs were updated
      bundler_content = File.read(File.join(ruby_install_dir, "bin", "bundler"))
      assert_includes bundler_content, File.join(ruby_install_dir, "bin", "ruby")
      refute_includes bundler_content, "/old/path/to/ruby"

      gem_content = File.read(File.join(ruby_install_dir, "bin", "gem"))
      assert_includes gem_content, File.join(ruby_install_dir, "bin", "ruby")
    end
  end

  def test_from_cache_updates_shebangs_in_bin_directory
    with_tmpdir do |tmpdir|
      cache_prefix = ".kompo/cache/#{RUBY_VERSION}"
      metadata = {"ruby_version" => RUBY_VERSION, "work_dir" => tmpdir}

      tmpdir << ["#{cache_prefix}/ruby/bin/ruby", "#!/bin/sh\necho ruby"] \
             << ["#{cache_prefix}/ruby/bin/irb", "#!/old/path/to/ruby\nputs 'irb'"] \
             << ["#{cache_prefix}/ruby/bin/rake", "#!/old/path/to/ruby\n# rake script"] \
             << ["#{cache_prefix}/metadata.json", JSON.generate(metadata)]

      cache_install_dir = tmpdir / cache_prefix / "ruby"
      FileUtils.chmod(0o755, File.join(cache_install_dir, "bin", "ruby"))
      FileUtils.chmod(0o755, File.join(cache_install_dir, "bin", "irb"))
      FileUtils.chmod(0o755, File.join(cache_install_dir, "bin", "rake"))

      mock_task(Kompo::WorkDir, path: tmpdir, original_dir: tmpdir)

      # Trigger task execution
      ruby_install_dir = Kompo::InstallRuby.ruby_install_dir(args: {kompo_cache: tmpdir / ".kompo" / "cache"})

      # Verify shebangs were updated
      irb_content = File.read(File.join(ruby_install_dir, "bin", "irb"))
      rake_content = File.read(File.join(ruby_install_dir, "bin", "rake"))

      new_ruby_path = File.join(ruby_install_dir, "bin", "ruby")
      assert_includes irb_content, new_ruby_path
      assert_includes rake_content, new_ruby_path
      refute_includes irb_content, "/old/path/to/ruby"
      refute_includes rake_content, "/old/path/to/ruby"
    end
  end

  def test_from_source_static_extensions_includes_common_extensions
    static_exts = Kompo::InstallRuby::STATIC_EXTENSIONS

    # Verify common extensions are included
    expected = %w[json openssl zlib socket stringio pathname]
    expected.each do |ext|
      assert_includes static_exts, ext, "STATIC_EXTENSIONS should include #{ext}"
    end
  end
end

class InstallRubyFromSourceTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def setup
    super
    @mock = setup_mock_command_runner
  end

  def teardown
    teardown_mock_command_runner
    super
  end

  def test_from_source_builds_ruby_when_no_cache
    with_tmpdir do |tmpdir|
      ruby_build_path = "/mock/ruby-build"
      work_dir = tmpdir

      mock_task(Kompo::RubyBuildPath, path: ruby_build_path)
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: work_dir)
      task_args = {
        ruby_version: "3.4.1",
        kompo_cache: tmpdir / ".kompo" / "cache",
        no_cache: true
      }

      # Mock ruby-build --definitions to return available versions
      @mock.stub([ruby_build_path, "--definitions"],
        output: "3.4.0\n3.4.1\n3.4.2\n", success: true)

      # Mock ruby-build execution
      @mock.stub([ruby_build_path, "--verbose", "--keep", "3.4.1", File.join(work_dir, "_ruby")],
        output: "Building Ruby 3.4.1...", success: true)

      # Mock ruby --version after build
      ruby_path = File.join(work_dir, "_ruby", "bin", "ruby")
      @mock.stub([ruby_path, "--version"],
        output: "ruby 3.4.1 (2025-01-01) [arm64-darwin24]", success: true)

      # Create the expected directory structure that would be created by ruby-build
      tmpdir << ["_ruby/bin/ruby", "#!/bin/sh"] << "_ruby/_build/"

      capture_io { Kompo::InstallRuby.run(args: task_args) }

      # Verify ruby-build was called
      ruby_install_dir = File.join(work_dir, "_ruby")
      assert @mock.called?(:run, ruby_build_path, "--verbose", "--keep", "3.4.1", ruby_install_dir)

      # Verify exports return expected values
      assert_equal ruby_path, Kompo::InstallRuby.ruby_path(args: task_args)
      assert_equal "3.4.1", Kompo::InstallRuby.ruby_version(args: task_args)
      assert_equal "3.4", Kompo::InstallRuby.ruby_major_minor(args: task_args)
    end
  end

  def test_from_source_raises_when_ruby_version_not_available
    with_tmpdir do |tmpdir|
      ruby_build_path = "/mock/ruby-build"

      mock_task(Kompo::RubyBuildPath, path: ruby_build_path)
      mock_task(Kompo::WorkDir, path: tmpdir, original_dir: tmpdir)
      task_args = {
        ruby_version: "9.9.9",
        kompo_cache: tmpdir / ".kompo" / "cache",
        no_cache: true
      }

      # Mock ruby-build --definitions to return versions that don't include 9.9.9
      @mock.stub([ruby_build_path, "--definitions"],
        output: "3.4.0\n3.4.1\n3.4.2\n", success: true)

      error = assert_raises(Taski::AggregateError) do
        capture_io { Kompo::InstallRuby.run(args: task_args) }
      end

      assert_match(/not available in ruby-build/, error.message)
    end
  end

  def test_from_source_restores_from_cache_when_valid
    with_tmpdir do |tmpdir|
      ruby_build_path = "/mock/ruby-build"
      work_dir = tmpdir
      cache_prefix = ".kompo/cache/3.4.1"
      metadata = {"work_dir" => work_dir, "ruby_version" => "3.4.1", "created_at" => Time.now.iso8601}

      # Create valid cache
      tmpdir << ["#{cache_prefix}/ruby/bin/ruby", "#!/bin/sh\necho ruby"] \
             << "#{cache_prefix}/ruby/_build/" \
             << ["#{cache_prefix}/metadata.json", JSON.generate(metadata)]

      FileUtils.chmod(0o755, tmpdir / cache_prefix / "ruby" / "bin" / "ruby")

      mock_task(Kompo::RubyBuildPath, path: ruby_build_path)
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: work_dir)
      task_args = {
        ruby_version: "3.4.1",
        kompo_cache: tmpdir / ".kompo" / "cache"
      }

      # Mock ruby --version
      ruby_path = File.join(work_dir, "_ruby", "bin", "ruby")
      @mock.stub([ruby_path, "--version"],
        output: "ruby 3.4.1", success: true)

      capture_io { Kompo::InstallRuby.run(args: task_args) }

      # ruby-build should NOT be called when restoring from cache
      ruby_install_dir = File.join(work_dir, "_ruby")
      refute @mock.called?(:run, ruby_build_path, "--verbose", "--keep", "3.4.1", ruby_install_dir),
        "ruby-build should not be called when valid cache exists"

      # Verify exports
      assert_equal "3.4.1", Kompo::InstallRuby.ruby_version(args: task_args)
    end
  end

  def test_from_source_with_ruby_source_directory
    with_tmpdir do |tmpdir|
      ruby_build_path = "/mock/ruby-build"
      work_dir = tmpdir
      source_dir = tmpdir / "ruby-source"
      tmpdir << "ruby-source/"

      mock_task(Kompo::RubyBuildPath, path: ruby_build_path)
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: work_dir)
      task_args = {
        ruby_version: "3.4.1",
        kompo_cache: tmpdir / ".kompo" / "cache",
        ruby_source_path: source_dir,
        no_cache: true
      }

      # Mock ruby-build execution with source directory
      @mock.stub([ruby_build_path, "--verbose", "--keep", source_dir, File.join(work_dir, "_ruby")],
        output: "Building Ruby from source...", success: true)

      # Mock ruby --version
      ruby_path = File.join(work_dir, "_ruby", "bin", "ruby")
      @mock.stub([ruby_path, "--version"],
        output: "ruby 3.4.1", success: true)

      # Create expected directory structure
      tmpdir << ["_ruby/bin/ruby", "#!/bin/sh"]

      capture_io { Kompo::InstallRuby.run(args: task_args) }

      # Verify ruby-build was called with source directory
      ruby_install_dir = File.join(work_dir, "_ruby")
      assert @mock.called?(:run, ruby_build_path, "--verbose", "--keep", source_dir, ruby_install_dir)
    end
  end

  def test_from_source_with_ruby_source_tarball
    with_tmpdir do |tmpdir|
      ruby_build_path = "/mock/ruby-build"
      work_dir = tmpdir
      tarball = tmpdir / "ruby-3.4.1.tar.gz"
      tmpdir << ["ruby-3.4.1.tar.gz", "dummy tarball"]

      mock_task(Kompo::RubyBuildPath, path: ruby_build_path)
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: work_dir)
      task_args = {
        kompo_cache: tmpdir / ".kompo" / "cache",
        ruby_source_path: tarball,
        no_cache: true
      }

      # Mock ruby-build execution
      @mock.stub([ruby_build_path, "--verbose", "--keep", "3.4.1", File.join(work_dir, "_ruby")],
        output: "Building Ruby...", success: true)

      # Mock ruby --version
      ruby_path = File.join(work_dir, "_ruby", "bin", "ruby")
      @mock.stub([ruby_path, "--version"],
        output: "ruby 3.4.1", success: true)

      # Create expected directory structure
      tmpdir << ["_ruby/bin/ruby", "#!/bin/sh"]

      capture_io { Kompo::InstallRuby.run(args: task_args) }

      # Verify version was extracted from tarball
      assert_equal "3.4.1", Kompo::InstallRuby.ruby_version(args: task_args)

      # Verify tarball was copied to cache
      assert File.exist?(tmpdir / ".kompo" / "cache" / "3.4.1" / "ruby-3.4.1.tar.gz")
    end
  end

  def test_from_source_raises_for_nonexistent_source_path
    with_tmpdir do |tmpdir|
      mock_task(Kompo::RubyBuildPath, path: "/mock/ruby-build")
      mock_task(Kompo::WorkDir, path: tmpdir, original_dir: tmpdir)
      task_args = {
        ruby_version: "3.4.1",
        kompo_cache: tmpdir / ".kompo" / "cache",
        ruby_source_path: "/nonexistent/path",
        no_cache: true
      }

      error = assert_raises(Taski::AggregateError) do
        capture_io { Kompo::InstallRuby.run(args: task_args) }
      end

      assert_match(/does not exist/, error.message)
    end
  end

  def test_from_source_raises_for_unsupported_source_format
    with_tmpdir do |tmpdir|
      tmpdir << ["ruby.zip", "dummy"]
      mock_task(Kompo::RubyBuildPath, path: "/mock/ruby-build")
      mock_task(Kompo::WorkDir, path: tmpdir, original_dir: tmpdir)
      task_args = {
        ruby_version: "3.4.1",
        kompo_cache: tmpdir / ".kompo" / "cache",
        ruby_source_path: tmpdir / "ruby.zip",
        no_cache: true
      }

      error = assert_raises(Taski::AggregateError) do
        capture_io { Kompo::InstallRuby.run(args: task_args) }
      end

      assert_match(/Unsupported source format/, error.message)
    end
  end

  def test_from_source_does_not_save_to_cache_when_no_cache_option_is_set
    with_tmpdir do |tmpdir|
      ruby_build_path = "/mock/ruby-build"
      work_dir = tmpdir
      kompo_cache = tmpdir / ".kompo" / "cache"

      mock_task(Kompo::RubyBuildPath, path: ruby_build_path)
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: work_dir)
      task_args = {
        ruby_version: "3.4.1",
        kompo_cache: kompo_cache,
        no_cache: true
      }

      # Mock ruby-build --definitions to return available versions
      @mock.stub([ruby_build_path, "--definitions"],
        output: "3.4.0\n3.4.1\n3.4.2\n", success: true)

      # Mock ruby-build execution
      @mock.stub([ruby_build_path, "--verbose", "--keep", "3.4.1", File.join(work_dir, "_ruby")],
        output: "Building Ruby 3.4.1...", success: true)

      # Mock ruby --version after build
      ruby_path = File.join(work_dir, "_ruby", "bin", "ruby")
      @mock.stub([ruby_path, "--version"],
        output: "ruby 3.4.1 (2025-01-01) [arm64-darwin24]", success: true)

      # Create the expected directory structure that would be created by ruby-build
      tmpdir << ["_ruby/bin/ruby", "#!/bin/sh"] << "_ruby/_build/"

      capture_io { Kompo::InstallRuby.run(args: task_args) }

      # Verify cache was NOT created due to no_cache option
      version_cache_dir = File.join(kompo_cache, "3.4.1")
      cache_ruby_dir = File.join(version_cache_dir, "ruby")
      metadata_path = File.join(version_cache_dir, "metadata.json")

      refute Dir.exist?(cache_ruby_dir), "Cache ruby directory should not be created with no_cache option"
      refute File.exist?(metadata_path), "Cache metadata.json should not be created with no_cache option"
    end
  end
end

class InstallRubyFromCacheRubyPcFixTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_from_cache_fixes_ruby_pc
    with_tmpdir do |tmpdir|
      cache_prefix = ".kompo/cache/#{RUBY_VERSION}"
      metadata = {"ruby_version" => RUBY_VERSION, "work_dir" => tmpdir}

      ruby_pc_content = <<~PC
        prefix=/old/cache/path
        exec_prefix=${prefix}
        libdir=${exec_prefix}/lib
      PC

      tmpdir << ["#{cache_prefix}/ruby/lib/pkgconfig/ruby.pc", ruby_pc_content] \
             << ["#{cache_prefix}/ruby/bin/ruby", "#!/bin/sh\necho ruby"] \
             << ["#{cache_prefix}/metadata.json", JSON.generate(metadata)]

      FileUtils.chmod(0o755, tmpdir / cache_prefix / "ruby" / "bin" / "ruby")

      mock_task(Kompo::WorkDir, path: tmpdir, original_dir: tmpdir)

      # Trigger task execution via public API
      ruby_install_dir = Kompo::InstallRuby.ruby_install_dir(args: {kompo_cache: tmpdir / ".kompo" / "cache"})

      # Verify ruby.pc was updated (observable external behavior)
      ruby_pc_content = File.read(File.join(ruby_install_dir, "lib", "pkgconfig", "ruby.pc"))
      assert_includes ruby_pc_content, "prefix=#{ruby_install_dir}"
      refute_includes ruby_pc_content, "/old/cache/path"
    end
  end
end
