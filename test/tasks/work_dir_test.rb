# frozen_string_literal: true

require_relative "../test_helper"
require "securerandom"

class WorkDirTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_work_dir_creates_temp_directory
    with_tmpdir do |tmpdir|
      # Mock Taski.args to use our temp directory for cache
      mock_args(kompo_cache: File.join(tmpdir, ".kompo", "cache"))

      path = Kompo::WorkDir.path
      original_dir = Kompo::WorkDir.original_dir

      assert path
      assert Dir.exist?(path)
      assert original_dir
      # Path should be resolved (no symlinks)
      assert_equal File.realpath(path), path
    end
  end

  def test_work_dir_uses_cached_work_dir_when_available
    with_tmpdir do |tmpdir|
      cached_work_dir = File.join(tmpdir, "cached_work")
      metadata = {"work_dir" => cached_work_dir, "ruby_version" => RUBY_VERSION}

      tmpdir << "cached_work/" \
             << ["cached_work/#{Kompo::WorkDir::MARKER_FILE}", "kompo-work-dir"] \
             << [".kompo/cache/#{RUBY_VERSION}/metadata.json", JSON.generate(metadata)]

      mock_args(kompo_cache: File.join(tmpdir, ".kompo", "cache"))

      path = Kompo::WorkDir.path

      assert_equal cached_work_dir, path
    end
  end

  def test_work_dir_handles_invalid_metadata_json
    with_tmpdir do |tmpdir|
      tmpdir << [".kompo/cache/#{RUBY_VERSION}/metadata.json", "not valid json"]

      mock_args(kompo_cache: File.join(tmpdir, ".kompo", "cache"))

      # Should fallback to creating new work_dir
      path = Kompo::WorkDir.path

      assert path
      assert Dir.exist?(path)
    end
  end

  def test_work_dir_recreates_cached_work_dir_when_directory_does_not_exist
    with_tmpdir do |tmpdir|
      cached_work_dir = File.join(tmpdir, "nonexistent_cached_work")
      metadata = {"work_dir" => cached_work_dir, "ruby_version" => RUBY_VERSION}

      # Create metadata file with cached work_dir path, but don't create the directory
      tmpdir << [".kompo/cache/#{RUBY_VERSION}/metadata.json", JSON.generate(metadata)]

      # Verify the directory doesn't exist
      refute Dir.exist?(cached_work_dir)

      mock_args(kompo_cache: File.join(tmpdir, ".kompo", "cache"))

      path = Kompo::WorkDir.path

      # Should recreate the cached work_dir path
      assert_equal cached_work_dir, path
      assert Dir.exist?(path)
      # Should also create the marker file
      assert File.exist?(File.join(path, Kompo::WorkDir::MARKER_FILE))
    end
  end

  def test_work_dir_warns_when_directory_exists_without_marker
    with_tmpdir do |tmpdir|
      cached_work_dir = File.join(tmpdir, "foreign_directory")
      metadata = {"work_dir" => cached_work_dir, "ruby_version" => RUBY_VERSION}

      # Create directory but without marker file (not created by Kompo)
      tmpdir << "foreign_directory/" \
             << [".kompo/cache/#{RUBY_VERSION}/metadata.json", JSON.generate(metadata)]

      mock_args(kompo_cache: File.join(tmpdir, ".kompo", "cache"))

      # Capture stderr to verify warning
      _out, err = capture_io do
        path = Kompo::WorkDir.path
        # Should NOT use the foreign directory, should create a new one
        refute_equal cached_work_dir, path
        assert Dir.exist?(path)
      end

      assert_match(/not a Kompo work directory/, err)
    end
  end

  def test_work_dir_rejects_cached_work_dir_at_nonexistent_root
    with_tmpdir do |tmpdir|
      cached_work_dir = "/nonexistent_root_path_#{SecureRandom.uuid}/work"

      metadata = {"work_dir" => cached_work_dir, "ruby_version" => RUBY_VERSION}
      tmpdir << [".kompo/cache/#{RUBY_VERSION}/metadata.json", JSON.generate(metadata)]

      mock_args(kompo_cache: File.join(tmpdir, ".kompo", "cache"))

      _out, err = capture_io do
        path = Kompo::WorkDir.path

        refute_equal cached_work_dir, path
        assert Dir.exist?(path)
        assert File.exist?(File.join(path, Kompo::WorkDir::MARKER_FILE))
      end

      assert_match(/outside.*temp/i, err)
    end
  end

  def test_work_dir_rejects_cached_work_dir_outside_tmpdir
    with_tmpdir do |tmpdir|
      cached_work_dir = "/etc/evil_kompo_work"
      metadata = {"work_dir" => cached_work_dir, "ruby_version" => RUBY_VERSION}

      tmpdir << [".kompo/cache/#{RUBY_VERSION}/metadata.json", JSON.generate(metadata)]

      mock_args(kompo_cache: File.join(tmpdir, ".kompo", "cache"))

      _out, err = capture_io do
        path = Kompo::WorkDir.path

        refute_equal cached_work_dir, path
        assert Dir.exist?(path)
        assert File.exist?(File.join(path, Kompo::WorkDir::MARKER_FILE))
      end

      assert_match(/outside.*temp/i, err)
    end
  end

  def test_work_dir_rejects_cached_work_dir_with_dot_dot_traversal
    with_tmpdir do |tmpdir|
      real_tmpdir = File.realpath(Dir.tmpdir)
      # Path that starts with tmpdir but escapes via ..
      cached_work_dir = "#{real_tmpdir}/../etc/evil"
      metadata = {"work_dir" => cached_work_dir, "ruby_version" => RUBY_VERSION}

      tmpdir << [".kompo/cache/#{RUBY_VERSION}/metadata.json", JSON.generate(metadata)]

      mock_args(kompo_cache: File.join(tmpdir, ".kompo", "cache"))

      _out, err = capture_io do
        path = Kompo::WorkDir.path

        refute_equal cached_work_dir, path
        assert Dir.exist?(path)
      end

      assert_match(/outside.*temp/i, err)
    end
  end

  def test_work_dir_ignores_cache_when_no_cache_option_is_set
    with_tmpdir do |tmpdir|
      cached_work_dir = File.join(tmpdir, "cached_work")
      metadata = {"work_dir" => cached_work_dir, "ruby_version" => RUBY_VERSION}

      tmpdir << "cached_work/" \
             << ["cached_work/#{Kompo::WorkDir::MARKER_FILE}", "kompo-work-dir"] \
             << [".kompo/cache/#{RUBY_VERSION}/metadata.json", JSON.generate(metadata)]

      # Set no_cache option
      mock_args(kompo_cache: File.join(tmpdir, ".kompo", "cache"), no_cache: true)

      path = Kompo::WorkDir.path

      # Should NOT use cached work_dir, should create a new one
      refute_equal cached_work_dir, path
      assert Dir.exist?(path)
      # New path should have marker file
      assert File.exist?(File.join(path, Kompo::WorkDir::MARKER_FILE))
    end
  end
end
