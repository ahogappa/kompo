# frozen_string_literal: true

require_relative "../test_helper"

class WorkDirTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_work_dir_creates_temp_directory
    Dir.mktmpdir do |tmpdir|
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
    Dir.mktmpdir do |tmpdir|
      cache_dir = File.join(tmpdir, ".kompo", "cache", RUBY_VERSION)
      cached_work_dir = File.join(tmpdir, "cached_work")
      FileUtils.mkdir_p([cache_dir, cached_work_dir])

      # Create marker file to identify this as a Kompo work directory
      File.write(File.join(cached_work_dir, Kompo::WorkDir::MARKER_FILE), "kompo-work-dir")

      # Create metadata file with cached work_dir path
      metadata = {"work_dir" => cached_work_dir, "ruby_version" => RUBY_VERSION}
      File.write(File.join(cache_dir, "metadata.json"), JSON.generate(metadata))

      mock_args(kompo_cache: File.join(tmpdir, ".kompo", "cache"))

      path = Kompo::WorkDir.path

      assert_equal cached_work_dir, path
    end
  end

  def test_work_dir_handles_invalid_metadata_json
    Dir.mktmpdir do |tmpdir|
      cache_dir = File.join(tmpdir, ".kompo", "cache", RUBY_VERSION)
      FileUtils.mkdir_p(cache_dir)

      # Create invalid JSON metadata file
      File.write(File.join(cache_dir, "metadata.json"), "not valid json")

      mock_args(kompo_cache: File.join(tmpdir, ".kompo", "cache"))

      # Should fallback to creating new work_dir
      path = Kompo::WorkDir.path

      assert path
      assert Dir.exist?(path)
    end
  end

  def test_work_dir_recreates_cached_work_dir_when_directory_does_not_exist
    Dir.mktmpdir do |tmpdir|
      cache_dir = File.join(tmpdir, ".kompo", "cache", RUBY_VERSION)
      # Use a path that doesn't exist yet (simulates CI cleanup between runs)
      cached_work_dir = File.join(tmpdir, "nonexistent_cached_work")
      FileUtils.mkdir_p(cache_dir)

      # Create metadata file with cached work_dir path, but don't create the directory
      metadata = {"work_dir" => cached_work_dir, "ruby_version" => RUBY_VERSION}
      File.write(File.join(cache_dir, "metadata.json"), JSON.generate(metadata))

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
    Dir.mktmpdir do |tmpdir|
      cache_dir = File.join(tmpdir, ".kompo", "cache", RUBY_VERSION)
      # Create directory but without marker file (not created by Kompo)
      cached_work_dir = File.join(tmpdir, "foreign_directory")
      FileUtils.mkdir_p([cache_dir, cached_work_dir])

      # Create metadata file pointing to the foreign directory
      metadata = {"work_dir" => cached_work_dir, "ruby_version" => RUBY_VERSION}
      File.write(File.join(cache_dir, "metadata.json"), JSON.generate(metadata))

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
end
