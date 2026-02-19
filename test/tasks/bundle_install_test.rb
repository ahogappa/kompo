# frozen_string_literal: true

require_relative "../test_helper"

class BundleInstallStructureTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_bundle_install_is_task
    assert Kompo::BundleInstall < Taski::Task
    assert_includes Kompo::BundleInstall.exported_methods, :bundle_ruby_dir
    assert_includes Kompo::BundleInstall.exported_methods, :bundler_config_path
  end
end

class BundleInstallTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_bundle_install_skips_when_no_gemfile
    with_tmpdir do |tmpdir|
      tmpdir << "work/"
      work_dir = tmpdir / "work"

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
    with_tmpdir do |tmpdir|
      gemfile_lock_content = "GEM\n  specs:\n"
      hash = Digest::SHA256.hexdigest(gemfile_lock_content)[0..15]
      bundle_cache_name = "bundle-#{hash}"
      cache_prefix = ".kompo/cache/3.4.1/#{bundle_cache_name}"

      tmpdir << ["work/Gemfile.lock", gemfile_lock_content] \
             << "#{cache_prefix}/bundle/" \
             << "#{cache_prefix}/.bundle/" \
             << ["#{cache_prefix}/metadata.json", '{"ruby_version": "3.4.1"}']

      work_dir = tmpdir / "work"

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyGemfile, gemfile_exists: true)
      mock_task(Kompo::InstallRuby, ruby_version: "3.4.1", ruby_major_minor: "3.4")
      # Execute and verify FromCache was selected (it restores bundle directory)
      Kompo::BundleInstall.bundle_ruby_dir(args: {cache_dir: tmpdir / ".kompo" / "cache"})
      assert Dir.exist?(File.join(work_dir, "bundle")), "FromCache should restore bundle directory"
    end
  end

  def test_bundle_install_from_cache_restores_bundle_directory
    with_tmpdir do |tmpdir|
      gemfile_lock_content = "GEM\n  specs:\n"
      hash = Digest::SHA256.hexdigest(gemfile_lock_content)[0..15]
      bundle_cache_name = "bundle-#{hash}"
      cache_prefix = ".kompo/cache/3.4.1/#{bundle_cache_name}"

      tmpdir << ["work/Gemfile.lock", gemfile_lock_content] \
             << ["#{cache_prefix}/bundle/ruby/3.4.0/gems/sinatra-4.0.0/lib/sinatra.rb", "# sinatra gem"] \
             << ["#{cache_prefix}/.bundle/config", "BUNDLE_PATH: bundle"] \
             << ["#{cache_prefix}/metadata.json", '{"ruby_version": "3.4.1"}']

      work_dir = tmpdir / "work"

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyGemfile, gemfile_exists: true)
      mock_task(Kompo::InstallRuby, ruby_version: "3.4.1", ruby_major_minor: "3.4")
      bundle_ruby_dir = Kompo::BundleInstall.bundle_ruby_dir(args: {cache_dir: tmpdir / ".kompo" / "cache"})

      # Verify cache was restored
      assert Dir.exist?(File.join(work_dir, "bundle"))
      assert Dir.exist?(File.join(work_dir, ".bundle"))
      assert File.exist?(File.join(work_dir, ".bundle", "config"))
      assert_equal File.join(work_dir, "bundle", "ruby", "3.4.0"), bundle_ruby_dir
    end
  end

  def test_bundle_install_from_cache_uses_bundle_cache_class
    with_tmpdir do |tmpdir|
      gemfile_lock_content = "GEM\n  specs:\n"
      tmpdir << ["work/Gemfile.lock", gemfile_lock_content]
      work_dir = tmpdir / "work"

      # Verify BundleCache.from_work_dir is used
      hash = Digest::SHA256.hexdigest(gemfile_lock_content)[0..15]
      bundle_cache = Kompo::BundleCache.from_work_dir(
        cache_dir: tmpdir / ".kompo" / "cache",
        ruby_version: "3.4.1",
        work_dir: work_dir
      )

      assert_instance_of Kompo::BundleCache, bundle_cache
      assert_equal "bundle-#{hash}", File.basename(bundle_cache.cache_dir)
    end
  end
end

class BundleInstallParseVersionTest < Minitest::Test
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

  def test_skips_bundler_install_with_invalid_version_format
    with_tmpdir do |tmpdir|
      # Gemfile.lock with malicious BUNDLED WITH value
      gemfile_lock_content = "GEM\n  remote: https://rubygems.org/\n  specs:\n    sinatra (4.0.0)\n\nBUNDLED WITH\n   2.5.0; evil\n"
      tmpdir << ["work/Gemfile", "source 'https://rubygems.org'\ngem 'sinatra'"] \
             << ["work/Gemfile.lock", gemfile_lock_content] \
             << "_ruby/"

      work_dir = tmpdir / "work"
      ruby_path = "/mock/ruby"
      bundler_path = "/mock/bundler"
      ruby_install_dir = tmpdir / "_ruby"

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyGemfile, gemfile_exists: true)
      mock_task(Kompo::InstallRuby,
        ruby_path: ruby_path,
        bundler_path: bundler_path,
        ruby_install_dir: ruby_install_dir,
        ruby_version: "3.4.1",
        ruby_major_minor: "3.4")
      # Mock bundler config set and install
      @mock.stub([ruby_path, bundler_path, "config", "set", "--local", "path", "bundle"],
        output: "", success: true)
      @mock.stub([ruby_path, bundler_path, "install"],
        output: "Bundle complete!", success: true)
      @mock.stub(["cc", "--version"],
        output: "Apple clang version 15.0.0", success: true)

      tmpdir << "work/bundle/ruby/3.4.0/" << ["work/.bundle/config", "BUNDLE_PATH: bundle"]

      capture_io { Kompo::BundleInstall.run(args: {cache_dir: tmpdir / ".kompo" / "cache", no_cache: true}) }

      # Should NOT attempt to check or install bundler (invalid version skipped)
      gem_path = File.join(ruby_install_dir, "bin", "gem")
      refute @mock.called?(:run, ruby_path, gem_path, "install", "bundler", "-v", "2.5.0; evil"),
        "Should not install bundler with invalid version format"
      refute @mock.called?(:capture, ruby_path, "-e", "require 'bundler'; puts Bundler::VERSION"),
        "Should not check bundler version when parsed version is invalid"
    end
  end
end

class BundleInstallFromSourceTest < Minitest::Test
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

  def test_from_source_installs_matching_bundler_when_version_differs
    with_tmpdir do |tmpdir|
      gemfile_lock_content = "GEM\n  remote: https://rubygems.org/\n  specs:\n    sinatra (4.0.0)\n\nBUNDLED WITH\n   2.5.0\n"
      tmpdir << ["work/Gemfile", "source 'https://rubygems.org'\ngem 'sinatra'"] \
             << ["work/Gemfile.lock", gemfile_lock_content] \
             << "_ruby/"

      work_dir = tmpdir / "work"
      ruby_path = "/mock/ruby"
      bundler_path = "/mock/bundler"
      ruby_install_dir = tmpdir / "_ruby"

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyGemfile, gemfile_exists: true)
      mock_task(Kompo::InstallRuby,
        ruby_path: ruby_path,
        bundler_path: bundler_path,
        ruby_install_dir: ruby_install_dir,
        ruby_version: "3.4.1",
        ruby_major_minor: "3.4")
      # Mock: get current bundler version (different from BUNDLED WITH)
      @mock.stub([ruby_path, "-e", "require 'bundler'; puts Bundler::VERSION"],
        output: "2.6.9", success: true)

      # Mock: gem install bundler
      gem_path = File.join(ruby_install_dir, "bin", "gem")
      @mock.stub([ruby_path, gem_path, "install", "bundler", "-v", "2.5.0"],
        output: "Successfully installed bundler-2.5.0", success: true)

      # Mock bundler config set and install
      @mock.stub([ruby_path, bundler_path, "config", "set", "--local", "path", "bundle"],
        output: "", success: true)
      @mock.stub([ruby_path, bundler_path, "install"],
        output: "Bundle complete!", success: true)
      @mock.stub(["cc", "--version"],
        output: "Apple clang version 15.0.0", success: true)

      # Create expected directory structure
      tmpdir << "work/bundle/ruby/3.4.0/" << ["work/.bundle/config", "BUNDLE_PATH: bundle"]

      capture_io { Kompo::BundleInstall.run(args: {cache_dir: tmpdir / ".kompo" / "cache", no_cache: true}) }

      assert @mock.called?(:run, ruby_path, gem_path, "install", "bundler", "-v", "2.5.0"),
        "Should install bundler matching BUNDLED WITH version"
    end
  end

  def test_from_source_skips_bundler_install_when_version_matches
    with_tmpdir do |tmpdir|
      gemfile_lock_content = "GEM\n  remote: https://rubygems.org/\n  specs:\n    sinatra (4.0.0)\n\nBUNDLED WITH\n   2.6.9\n"
      tmpdir << ["work/Gemfile", "source 'https://rubygems.org'\ngem 'sinatra'"] \
             << ["work/Gemfile.lock", gemfile_lock_content] \
             << "_ruby/"

      work_dir = tmpdir / "work"
      ruby_path = "/mock/ruby"
      bundler_path = "/mock/bundler"
      ruby_install_dir = tmpdir / "_ruby"

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyGemfile, gemfile_exists: true)
      mock_task(Kompo::InstallRuby,
        ruby_path: ruby_path,
        bundler_path: bundler_path,
        ruby_install_dir: ruby_install_dir,
        ruby_version: "3.4.1",
        ruby_major_minor: "3.4")
      # Mock: get current bundler version (same as BUNDLED WITH)
      @mock.stub([ruby_path, "-e", "require 'bundler'; puts Bundler::VERSION"],
        output: "2.6.9", success: true)

      # Mock bundler config set and install
      @mock.stub([ruby_path, bundler_path, "config", "set", "--local", "path", "bundle"],
        output: "", success: true)
      @mock.stub([ruby_path, bundler_path, "install"],
        output: "Bundle complete!", success: true)
      @mock.stub(["cc", "--version"],
        output: "Apple clang version 15.0.0", success: true)

      # Create expected directory structure
      tmpdir << "work/bundle/ruby/3.4.0/" << ["work/.bundle/config", "BUNDLE_PATH: bundle"]

      capture_io { Kompo::BundleInstall.run(args: {cache_dir: tmpdir / ".kompo" / "cache", no_cache: true}) }

      gem_path = File.join(ruby_install_dir, "bin", "gem")
      refute @mock.called?(:run, ruby_path, gem_path, "install", "bundler", "-v", "2.6.9"),
        "Should not install bundler when version already matches"
    end
  end

  def test_from_source_skips_bundler_install_when_bundled_with_is_empty
    with_tmpdir do |tmpdir|
      # BUNDLED WITH with no version on next line
      gemfile_lock_content = "GEM\n  remote: https://rubygems.org/\n  specs:\n    sinatra (4.0.0)\n\nBUNDLED WITH\n"
      tmpdir << ["work/Gemfile", "source 'https://rubygems.org'\ngem 'sinatra'"] \
             << ["work/Gemfile.lock", gemfile_lock_content] \
             << "_ruby/"

      work_dir = tmpdir / "work"
      ruby_path = "/mock/ruby"
      bundler_path = "/mock/bundler"
      ruby_install_dir = tmpdir / "_ruby"

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyGemfile, gemfile_exists: true)
      mock_task(Kompo::InstallRuby,
        ruby_path: ruby_path,
        bundler_path: bundler_path,
        ruby_install_dir: ruby_install_dir,
        ruby_version: "3.4.1",
        ruby_major_minor: "3.4")
      # Mock bundler config set and install
      @mock.stub([ruby_path, bundler_path, "config", "set", "--local", "path", "bundle"],
        output: "", success: true)
      @mock.stub([ruby_path, bundler_path, "install"],
        output: "Bundle complete!", success: true)
      @mock.stub(["cc", "--version"],
        output: "Apple clang version 15.0.0", success: true)

      tmpdir << "work/bundle/ruby/3.4.0/" << ["work/.bundle/config", "BUNDLE_PATH: bundle"]

      capture_io { Kompo::BundleInstall.run(args: {cache_dir: tmpdir / ".kompo" / "cache", no_cache: true}) }

      refute @mock.called?(:capture, ruby_path, "-e", "require 'bundler'; puts Bundler::VERSION"),
        "Should not check bundler version when BUNDLED WITH is empty"
    end
  end

  def test_from_source_does_not_save_to_cache_when_no_cache_option_is_set
    with_tmpdir do |tmpdir|
      gemfile_lock_content = "GEM\n  remote: https://rubygems.org/\n  specs:\n    sinatra (4.0.0)\n"
      tmpdir << ["work/Gemfile", "source 'https://rubygems.org'\ngem 'sinatra'"] \
             << ["work/Gemfile.lock", gemfile_lock_content]

      work_dir = tmpdir / "work"
      ruby_path = "/mock/ruby"
      bundler_path = "/mock/bundler"
      cache_dir = tmpdir / ".kompo" / "cache"

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyGemfile, gemfile_exists: true)
      mock_task(Kompo::InstallRuby,
        ruby_path: ruby_path,
        bundler_path: bundler_path,
        ruby_version: "3.4.1",
        ruby_major_minor: "3.4")
      # Mock bundler config set command
      @mock.stub([ruby_path, bundler_path, "config", "set", "--local", "path", "bundle"],
        output: "", success: true)

      # Mock bundle install command
      @mock.stub([ruby_path, bundler_path, "install"],
        output: "Bundle complete!", success: true)

      # Mock cc --version for clang check
      @mock.stub(["cc", "--version"],
        output: "Apple clang version 15.0.0", success: true)

      # Create expected directory structure that bundle install would create
      tmpdir << "work/bundle/ruby/3.4.0/" << ["work/.bundle/config", "BUNDLE_PATH: bundle"]

      capture_io { Kompo::BundleInstall.run(args: {cache_dir: cache_dir, no_cache: true}) }

      # Verify bundle install was called
      assert @mock.called?(:run, ruby_path, bundler_path, "install")

      # Verify cache was NOT created due to no_cache option
      hash = Digest::SHA256.hexdigest(gemfile_lock_content)[0..15]
      bundle_cache_name = "bundle-#{hash}"
      version_cache_dir = File.join(cache_dir, "3.4.1")
      bundle_cache_dir = File.join(version_cache_dir, bundle_cache_name)

      refute Dir.exist?(bundle_cache_dir), "Bundle cache directory should not be created with no_cache option"
    end
  end
end
