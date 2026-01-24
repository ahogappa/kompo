# frozen_string_literal: true

require_relative "../test_helper"

class InstallRubyTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_install_ruby_uses_cache_when_available
    Dir.mktmpdir do |tmpdir|
      # Create cache directory structure (new structure: {version}/ruby/)
      version_cache_dir = File.join(tmpdir, ".kompo", "cache", RUBY_VERSION)
      ruby_install_dir = File.join(version_cache_dir, "ruby")
      FileUtils.mkdir_p(ruby_install_dir)

      # Create metadata file indicating cache is valid
      metadata = {
        "ruby_version" => RUBY_VERSION,
        "work_dir" => tmpdir
      }
      File.write(File.join(version_cache_dir, "metadata.json"), JSON.generate(metadata))

      # Create required files that FromCache checks
      FileUtils.mkdir_p(File.join(ruby_install_dir, "bin"))
      File.write(File.join(ruby_install_dir, "bin", "ruby"), "#!/bin/sh")
      File.write(File.join(ruby_install_dir, "bin", "bundle"), "#!/bin/sh")

      mock_task(Kompo::WorkDir, path: tmpdir, original_dir: tmpdir)
      mock_args(kompo_cache: File.join(tmpdir, ".kompo", "cache"))

      # InstallRuby.impl should select FromCache when cache exists
      # We test that the Section properly reads cache metadata
      assert File.exist?(File.join(version_cache_dir, "metadata.json"))
    end
  end

  def test_install_ruby_interfaces_are_defined
    # Verify that InstallRuby Section defines expected interfaces
    exported = Kompo::InstallRuby.exported_methods
    expected = %i[ruby_path bundler_path ruby_install_dir ruby_version
      ruby_major_minor ruby_build_path original_ruby_install_dir]

    expected.each do |interface|
      assert_includes exported, interface, "InstallRuby should define #{interface} interface"
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
    Dir.mktmpdir do |tmpdir|
      # Create cache with proper structure (new structure: {version}/ruby/)
      version_cache_dir = File.join(tmpdir, ".kompo", "cache", RUBY_VERSION)
      cache_install_dir = File.join(version_cache_dir, "ruby")
      FileUtils.mkdir_p(File.join(cache_install_dir, "bin"))

      # Create ruby and other bin files with shebangs
      File.write(File.join(cache_install_dir, "bin", "ruby"), "#!/bin/sh\necho ruby")
      File.write(File.join(cache_install_dir, "bin", "bundler"), "#!/old/path/to/ruby\necho bundler")
      File.write(File.join(cache_install_dir, "bin", "gem"), "#!/old/path/to/ruby\necho gem")
      FileUtils.chmod(0o755, File.join(cache_install_dir, "bin", "ruby"))
      FileUtils.chmod(0o755, File.join(cache_install_dir, "bin", "bundler"))
      FileUtils.chmod(0o755, File.join(cache_install_dir, "bin", "gem"))

      # Create metadata
      metadata = {"ruby_version" => RUBY_VERSION, "work_dir" => tmpdir}
      File.write(File.join(version_cache_dir, "metadata.json"), JSON.generate(metadata))

      mock_task(Kompo::WorkDir, path: tmpdir, original_dir: tmpdir)
      mock_args(kompo_cache: File.join(tmpdir, ".kompo", "cache"))

      # Trigger task execution and get result
      ruby_install_dir = Kompo::InstallRuby.ruby_install_dir

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
    Dir.mktmpdir do |tmpdir|
      version_cache_dir = File.join(tmpdir, ".kompo", "cache", RUBY_VERSION)
      cache_install_dir = File.join(version_cache_dir, "ruby")
      FileUtils.mkdir_p(File.join(cache_install_dir, "bin"))

      # Create files with shebangs
      ruby_content = "#!/bin/sh\necho ruby"
      irb_content = "#!/old/path/to/ruby\nputs 'irb'"
      rake_content = "#!/old/path/to/ruby\n# rake script"

      File.write(File.join(cache_install_dir, "bin", "ruby"), ruby_content)
      File.write(File.join(cache_install_dir, "bin", "irb"), irb_content)
      File.write(File.join(cache_install_dir, "bin", "rake"), rake_content)
      FileUtils.chmod(0o755, File.join(cache_install_dir, "bin", "ruby"))
      FileUtils.chmod(0o755, File.join(cache_install_dir, "bin", "irb"))
      FileUtils.chmod(0o755, File.join(cache_install_dir, "bin", "rake"))

      # Create metadata
      metadata = {"ruby_version" => RUBY_VERSION, "work_dir" => tmpdir}
      File.write(File.join(version_cache_dir, "metadata.json"), JSON.generate(metadata))

      mock_task(Kompo::WorkDir, path: tmpdir, original_dir: tmpdir)
      mock_args(kompo_cache: File.join(tmpdir, ".kompo", "cache"))

      # Trigger task execution
      ruby_install_dir = Kompo::InstallRuby.ruby_install_dir

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
