# frozen_string_literal: true

require_relative '../test_helper'

class BundleInstallTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_bundle_install_skips_when_no_gemfile
    Dir.mktmpdir do |tmpdir|
      work_dir = File.join(tmpdir, 'work')
      FileUtils.mkdir_p(work_dir)

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyGemfile, gemfile_exists: false)
      mock_task(Kompo::InstallRuby,
                bundler_path: '/path/to/bundler',
                ruby_major_minor: '3.4')

      bundle_ruby_dir = Kompo::BundleInstall.bundle_ruby_dir
      bundler_config_path = Kompo::BundleInstall.bundler_config_path

      assert_nil bundle_ruby_dir
      assert_nil bundler_config_path
      assert_task_accessed(Kompo::CopyGemfile, :gemfile_exists)
    end
  end

  def test_bundle_install_sets_paths_when_gemfile_exists
    Dir.mktmpdir do |tmpdir|
      work_dir = File.join(tmpdir, 'work')
      FileUtils.mkdir_p(work_dir)
      File.write(File.join(work_dir, 'Gemfile'), "source 'https://rubygems.org'")
      File.write(File.join(work_dir, 'Gemfile.lock'), "GEM\n  specs:\n")

      # Create bundle directory that would be created by bundle install
      bundle_dir = File.join(work_dir, 'bundle', 'ruby', '3.4.0')
      bundle_config_dir = File.join(work_dir, '.bundle')
      FileUtils.mkdir_p(bundle_dir)
      FileUtils.mkdir_p(bundle_config_dir)
      File.write(File.join(bundle_config_dir, 'config'), 'BUNDLE_PATH: bundle')

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyGemfile, gemfile_exists: true)
      mock_task(Kompo::InstallRuby,
                bundler_path: '/path/to/bundler',
                ruby_path: '/path/to/ruby',
                ruby_version: '3.4.1',
                ruby_major_minor: '3.4')
      mock_args(kompo_cache: File.join(tmpdir, '.kompo', 'cache'))

      # Stub system calls to avoid actual bundle install
      Kompo::BundleInstall::FromSource.define_method(:system) do |*_args, **_kwargs|
        true
      end

      begin
        bundle_ruby_dir = Kompo::BundleInstall.bundle_ruby_dir
        bundler_config_path = Kompo::BundleInstall.bundler_config_path

        assert_equal File.join(work_dir, 'bundle', 'ruby', '3.4.0'), bundle_ruby_dir
        assert_equal File.join(work_dir, '.bundle', 'config'), bundler_config_path
      ensure
        Kompo::BundleInstall::FromSource.remove_method(:system)
      end
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
      work_dir = File.join(tmpdir, 'work')
      FileUtils.mkdir_p(work_dir)
      gemfile_lock_content = "GEM\n  specs:\n"
      File.write(File.join(work_dir, 'Gemfile.lock'), gemfile_lock_content)

      # Calculate expected cache name (new structure: {version}/bundle-{hash})
      hash = Digest::SHA256.hexdigest(gemfile_lock_content)[0..15]
      bundle_cache_name = "bundle-#{hash}"
      version_cache_dir = File.join(tmpdir, '.kompo', 'cache', '3.4.1')
      cache_dir = File.join(version_cache_dir, bundle_cache_name)

      # Create cache with content
      cache_bundle_dir = File.join(cache_dir, 'bundle', 'ruby', '3.4.0', 'gems', 'sinatra-4.0.0')
      cache_bundle_lib_dir = File.join(cache_bundle_dir, 'lib')
      cache_bundle_config = File.join(cache_dir, '.bundle')
      FileUtils.mkdir_p(cache_bundle_lib_dir)
      FileUtils.mkdir_p(cache_bundle_config)
      File.write(File.join(cache_bundle_lib_dir, 'sinatra.rb'), '# sinatra gem')
      File.write(File.join(cache_bundle_config, 'config'), 'BUNDLE_PATH: bundle')
      File.write(File.join(cache_dir, 'metadata.json'), '{"ruby_version": "3.4.1"}')

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyGemfile, gemfile_exists: true)
      mock_task(Kompo::InstallRuby, ruby_version: '3.4.1', ruby_major_minor: '3.4')
      mock_args(kompo_cache: File.join(tmpdir, '.kompo', 'cache'))

      bundle_ruby_dir = Kompo::BundleInstall.bundle_ruby_dir

      # Verify cache was restored
      assert Dir.exist?(File.join(work_dir, 'bundle'))
      assert Dir.exist?(File.join(work_dir, '.bundle'))
      assert File.exist?(File.join(work_dir, '.bundle', 'config'))
      assert_equal File.join(work_dir, 'bundle', 'ruby', '3.4.0'), bundle_ruby_dir
    end
  end

  def test_bundle_install_from_source_saves_to_cache
    Dir.mktmpdir do |tmpdir|
      # Resolve tmpdir to real path (macOS /var -> /private/var symlink)
      tmpdir = File.realpath(tmpdir)

      work_dir = File.join(tmpdir, 'work')
      FileUtils.mkdir_p(work_dir)
      gemfile_lock_content = "GEM\n  specs:\n"
      File.write(File.join(work_dir, 'Gemfile'), "source 'https://rubygems.org'")
      File.write(File.join(work_dir, 'Gemfile.lock'), gemfile_lock_content)

      # Create bundle directory that would be created by bundle install
      bundle_dir = File.join(work_dir, 'bundle', 'ruby', '3.4.0', 'gems')
      bundle_config_dir = File.join(work_dir, '.bundle')
      FileUtils.mkdir_p(bundle_dir)
      FileUtils.mkdir_p(bundle_config_dir)
      File.write(File.join(bundle_config_dir, 'config'), 'BUNDLE_PATH: bundle')

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyGemfile, gemfile_exists: true)
      mock_task(Kompo::InstallRuby,
                ruby_version: '3.4.1',
                ruby_major_minor: '3.4',
                ruby_path: '/path/to/ruby',
                bundler_path: '/path/to/bundler')
      mock_args(kompo_cache: File.join(tmpdir, '.kompo', 'cache'))

      # Stub system calls
      Kompo::BundleInstall::FromSource.define_method(:system) do |*_args, **_kwargs|
        true
      end

      begin
        Kompo::BundleInstall.bundle_ruby_dir

        # Verify cache was created (new structure: {version}/bundle-{hash})
        hash = Digest::SHA256.hexdigest(gemfile_lock_content)[0..15]
        bundle_cache_name = "bundle-#{hash}"
        version_cache_dir = File.join(tmpdir, '.kompo', 'cache', '3.4.1')
        cache_dir = File.join(version_cache_dir, bundle_cache_name)

        assert Dir.exist?(cache_dir), 'Cache directory should exist'
        assert Dir.exist?(File.join(cache_dir, 'bundle')), 'Cache bundle directory should exist'
        assert Dir.exist?(File.join(cache_dir, '.bundle')), 'Cache .bundle directory should exist'
        assert File.exist?(File.join(cache_dir, 'metadata.json')), 'Cache metadata should exist'

        # Verify metadata content
        metadata = JSON.parse(File.read(File.join(cache_dir, 'metadata.json')))
        assert_equal '3.4.1', metadata['ruby_version']
        assert_equal hash, metadata['gemfile_lock_hash']
      ensure
        Kompo::BundleInstall::FromSource.remove_method(:system)
      end
    end
  end

  def test_bundle_cache_helpers_included_in_from_cache
    assert Kompo::BundleInstall::FromCache.include?(Kompo::BundleCacheHelpers)
  end

  def test_bundle_cache_helpers_included_in_from_source
    assert Kompo::BundleInstall::FromSource.include?(Kompo::BundleCacheHelpers)
  end

  def test_bundle_cache_helpers_included_in_bundle_install
    assert Kompo::BundleInstall.include?(Kompo::BundleCacheHelpers)
  end
end
