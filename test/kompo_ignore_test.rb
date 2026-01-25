# frozen_string_literal: true

require_relative "test_helper"

class KompoIgnoreTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  private

  def create_ignore_file(content)
    File.write(File.join(@temp_dir, ".kompoignore"), content)
    Kompo::KompoIgnore.new(@temp_dir)
  end

  def test_enabled_returns_false_when_no_kompoignore_file
    ignore = Kompo::KompoIgnore.new(@temp_dir)
    refute ignore.enabled?
  end

  def test_enabled_returns_true_when_kompoignore_exists
    ignore = create_ignore_file("*.log\n")
    assert ignore.enabled?
  end

  def test_ignore_returns_false_when_not_enabled
    ignore = Kompo::KompoIgnore.new(@temp_dir)
    refute ignore.ignore?("test.log")
  end

  def test_ignore_matches_simple_glob_pattern
    ignore = create_ignore_file("*.log\n")

    assert ignore.ignore?("test.log")
    assert ignore.ignore?("debug.log")
    refute ignore.ignore?("test.rb")
  end

  def test_ignore_matches_directory_pattern
    ignore = create_ignore_file("tmp/\n")

    assert ignore.ignore?("tmp/test.rb")
    assert ignore.ignore?("tmp/cache/data.txt")
    refute ignore.ignore?("src/tmp.rb")
  end

  def test_ignore_matches_double_star_pattern
    ignore = create_ignore_file("**/cache/\n")

    assert ignore.ignore?("cache/data.txt")
    assert ignore.ignore?("app/cache/data.txt")
    assert ignore.ignore?("deep/nested/cache/data.txt")
    refute ignore.ignore?("src/cached.rb")
  end

  def test_ignore_handles_negation_pattern
    ignore = create_ignore_file(<<~IGNORE)
      *.log
      !important.log
    IGNORE

    assert ignore.ignore?("test.log")
    assert ignore.ignore?("debug.log")
    refute ignore.ignore?("important.log")
  end

  def test_ignore_handles_comments
    ignore = create_ignore_file(<<~IGNORE)
      # This is a comment
      *.log
      # Another comment
      tmp/
    IGNORE

    assert ignore.ignore?("test.log")
    assert ignore.ignore?("tmp/file.txt")
    refute ignore.ignore?("test.rb")
  end

  def test_ignore_handles_empty_lines
    ignore = create_ignore_file(<<~IGNORE)
      *.log

      tmp/

    IGNORE

    assert ignore.ignore?("test.log")
    assert ignore.ignore?("tmp/file.txt")
  end

  def test_ignore_multiple_patterns
    ignore = create_ignore_file(<<~IGNORE)
      *.log
      *.tmp
      node_modules/
      spec/
      test/
    IGNORE

    assert ignore.ignore?("debug.log")
    assert ignore.ignore?("cache.tmp")
    assert ignore.ignore?("node_modules/package.json")
    assert ignore.ignore?("spec/test_spec.rb")
    assert ignore.ignore?("test/test_file.rb")
    refute ignore.ignore?("app/main.rb")
  end

  def test_ignore_handles_path_with_leading_slash
    ignore = create_ignore_file("/config.local.yml\n")

    assert ignore.ignore?("config.local.yml")
    refute ignore.ignore?("subdir/config.local.yml")
  end
end
