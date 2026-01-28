# frozen_string_literal: true

require_relative "../test_helper"

class BundleInstallTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_bundle_install_skips_when_no_gemfile
    Dir.mktmpdir do |tmpdir|
      work_dir = File.join(tmpdir, "work")
      FileUtils.mkdir_p(work_dir)

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyGemfile, gemfile_exists: false)
      mock_task(Kompo::InstallRuby,
        bundler_path: "/path/to/bundler",
        ruby_major_minor: "3.4")

      bundle_ruby_dir = Kompo::BundleInstall.bundle_ruby_dir
      bundler_config_path = Kompo::BundleInstall.bundler_config_path

      assert_nil bundle_ruby_dir
      assert_nil bundler_config_path
      assert_task_accessed(Kompo::CopyGemfile, :gemfile_exists)
    end
  end

  def test_bundle_install_selects_from_cache_when_cache_exists
    Dir.mktmpdir do |tmpdir|
      work_dir = File.join(tmpdir, "work")
      FileUtils.mkdir_p(work_dir)
      gemfile_lock_content = "GEM\n  specs:\n"
      File.write(File.join(work_dir, "Gemfile.lock"), gemfile_lock_content)

      # Calculate expected cache name
      hash = Digest::SHA256.hexdigest(gemfile_lock_content)[0..15]
      bundle_cache_name = "bundle-#{hash}"
      version_cache_dir = File.join(tmpdir, ".kompo", "cache", "3.4.1")
      cache_dir = File.join(version_cache_dir, bundle_cache_name)

      # Create complete cache structure
      FileUtils.mkdir_p(File.join(cache_dir, "bundle"))
      FileUtils.mkdir_p(File.join(cache_dir, ".bundle"))
      File.write(File.join(cache_dir, "metadata.json"), '{"ruby_version": "3.4.1"}')

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyGemfile, gemfile_exists: true)
      mock_task(Kompo::InstallRuby, ruby_version: "3.4.1", ruby_major_minor: "3.4")
      mock_args(cache_dir: File.join(tmpdir, ".kompo", "cache"))

      # Execute and verify FromCache was selected (it restores bundle directory)
      Kompo::BundleInstall.bundle_ruby_dir
      assert Dir.exist?(File.join(work_dir, "bundle")), "FromCache should restore bundle directory"
    end
  end

  def test_bundle_install_is_section
    assert Kompo::BundleInstall < Taski::Section
    assert_includes Kompo::BundleInstall.exported_methods, :bundle_ruby_dir
    assert_includes Kompo::BundleInstall.exported_methods, :bundler_config_path
  end

  def test_bundle_install_has_from_cache_class
    assert_kind_of Class, Kompo::BundleInstall::FromCache
    assert Kompo::BundleInstall::FromCache < Taski::Task
  end

  def test_bundle_install_has_from_source_class
    assert_kind_of Class, Kompo::BundleInstall::FromSource
    assert Kompo::BundleInstall::FromSource < Taski::Task
  end

  def test_bundle_install_has_skip_class
    assert_kind_of Class, Kompo::BundleInstall::Skip
    assert Kompo::BundleInstall::Skip < Taski::Task
  end

  def test_bundle_install_from_cache_restores_bundle_directory
    Dir.mktmpdir do |tmpdir|
      work_dir = File.join(tmpdir, "work")
      FileUtils.mkdir_p(work_dir)
      gemfile_lock_content = "GEM\n  specs:\n"
      File.write(File.join(work_dir, "Gemfile.lock"), gemfile_lock_content)

      # Calculate expected cache name (new structure: {version}/bundle-{hash})
      hash = Digest::SHA256.hexdigest(gemfile_lock_content)[0..15]
      bundle_cache_name = "bundle-#{hash}"
      version_cache_dir = File.join(tmpdir, ".kompo", "cache", "3.4.1")
      cache_dir = File.join(version_cache_dir, bundle_cache_name)

      # Create cache with content
      cache_bundle_dir = File.join(cache_dir, "bundle", "ruby", "3.4.0", "gems", "sinatra-4.0.0")
      cache_bundle_lib_dir = File.join(cache_bundle_dir, "lib")
      cache_bundle_config = File.join(cache_dir, ".bundle")
      FileUtils.mkdir_p(cache_bundle_lib_dir)
      FileUtils.mkdir_p(cache_bundle_config)
      File.write(File.join(cache_bundle_lib_dir, "sinatra.rb"), "# sinatra gem")
      File.write(File.join(cache_bundle_config, "config"), "BUNDLE_PATH: bundle")
      File.write(File.join(cache_dir, "metadata.json"), '{"ruby_version": "3.4.1"}')

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyGemfile, gemfile_exists: true)
      mock_task(Kompo::InstallRuby, ruby_version: "3.4.1", ruby_major_minor: "3.4")
      mock_args(cache_dir: File.join(tmpdir, ".kompo", "cache"))

      bundle_ruby_dir = Kompo::BundleInstall.bundle_ruby_dir

      # Verify cache was restored
      assert Dir.exist?(File.join(work_dir, "bundle"))
      assert Dir.exist?(File.join(work_dir, ".bundle"))
      assert File.exist?(File.join(work_dir, ".bundle", "config"))
      assert_equal File.join(work_dir, "bundle", "ruby", "3.4.0"), bundle_ruby_dir
    end
  end

  def test_bundle_install_from_cache_uses_bundle_cache_class
    Dir.mktmpdir do |tmpdir|
      work_dir = File.join(tmpdir, "work")
      FileUtils.mkdir_p(work_dir)
      gemfile_lock_content = "GEM\n  specs:\n"
      File.write(File.join(work_dir, "Gemfile.lock"), gemfile_lock_content)

      # Verify BundleCache.from_work_dir is used
      hash = Digest::SHA256.hexdigest(gemfile_lock_content)[0..15]
      bundle_cache = Kompo::BundleCache.from_work_dir(
        cache_dir: File.join(tmpdir, ".kompo", "cache"),
        ruby_version: "3.4.1",
        work_dir: work_dir
      )

      assert_instance_of Kompo::BundleCache, bundle_cache
      assert_equal "bundle-#{hash}", File.basename(bundle_cache.cache_dir)
    end
  end
end
