# frozen_string_literal: true

require_relative "test_helper"

class TmpDirTest < Minitest::Test
  def test_to_s_returns_path
    with_tmpdir do |tmpdir|
      assert_kind_of String, tmpdir.to_s
      assert Dir.exist?(tmpdir.to_s)
    end
  end

  def test_works_with_file_join
    with_tmpdir do |tmpdir|
      path = File.join(tmpdir, "foo")
      assert path.end_with?("/foo")
    end
  end

  def test_shovel_string_creates_empty_file
    with_tmpdir do |tmpdir|
      tmpdir << "empty.txt"
      assert File.exist?(tmpdir / "empty.txt")
      assert_equal "", File.read(tmpdir / "empty.txt")
    end
  end

  def test_shovel_array_creates_file_with_content
    with_tmpdir do |tmpdir|
      tmpdir << ["hello.txt", "hello world"]
      assert_equal "hello world", File.read(tmpdir / "hello.txt")
    end
  end

  def test_shovel_string_with_trailing_slash_creates_directory
    with_tmpdir do |tmpdir|
      tmpdir << "subdir/"
      assert Dir.exist?(tmpdir / "subdir")
    end
  end

  def test_shovel_nested_path_creates_parent_dirs
    with_tmpdir do |tmpdir|
      tmpdir << ["deep/nested/file.txt", "content"]
      assert_equal "content", File.read(tmpdir / "deep/nested/file.txt")
    end
  end

  def test_shovel_nested_empty_file_creates_parent_dirs
    with_tmpdir do |tmpdir|
      tmpdir << "deep/nested/empty.txt"
      assert File.exist?(tmpdir / "deep/nested/empty.txt")
    end
  end

  def test_shovel_nested_directory_creates_full_path
    with_tmpdir do |tmpdir|
      tmpdir << "a/b/c/"
      assert Dir.exist?(tmpdir / "a/b/c")
    end
  end

  def test_shovel_single_element_array_creates_empty_file
    with_tmpdir do |tmpdir|
      tmpdir << ["empty.txt"]
      assert File.exist?(tmpdir / "empty.txt")
      assert_equal "", File.read(tmpdir / "empty.txt")
    end
  end

  def test_shovel_single_element_array_with_trailing_slash_creates_directory
    with_tmpdir do |tmpdir|
      tmpdir << ["subdir/"]
      assert Dir.exist?(tmpdir / "subdir")
    end
  end

  def test_shovel_single_element_array_with_nested_path_creates_parent_dirs
    with_tmpdir do |tmpdir|
      tmpdir << ["deep/nested/empty.txt"]
      assert File.exist?(tmpdir / "deep/nested/empty.txt")
    end
  end

  def test_shovel_array_with_three_or_more_elements_raises_error
    with_tmpdir do |tmpdir|
      assert_raises(ArgumentError) { tmpdir << ["a.txt", "content", "extra"] }
    end
  end

  def test_shovel_empty_array_raises_error
    with_tmpdir do |tmpdir|
      assert_raises(ArgumentError) { tmpdir << [] }
    end
  end

  def test_shovel_unsupported_type_raises_error
    with_tmpdir do |tmpdir|
      assert_raises(ArgumentError) { tmpdir << 123 }
      assert_raises(ArgumentError) { tmpdir << nil }
      assert_raises(ArgumentError) { tmpdir << {name: "file"} }
    end
  end

  def test_slash_joins_path
    with_tmpdir do |tmpdir|
      result = tmpdir / "work"
      assert_kind_of TmpDir, result
      assert_equal File.join(tmpdir.to_s, "work"), result.to_s
    end
  end

  def test_slash_chains_for_nested_path
    with_tmpdir do |tmpdir|
      result = tmpdir / "work" / "src"
      assert_kind_of TmpDir, result
      assert_equal File.join(tmpdir.to_s, "work", "src"), result.to_s
    end
  end

  def test_slash_result_works_with_file_operations
    with_tmpdir do |tmpdir|
      tmpdir << ["work/hoge.rb", "puts 'hello'"]
      assert_equal "puts 'hello'", File.read(tmpdir / "work" / "hoge.rb")
    end
  end

  def test_shovel_returns_self_for_chaining
    with_tmpdir do |tmpdir|
      tmpdir << "a.txt" << ["b.txt", "B"] << "subdir/"
      assert File.exist?(tmpdir / "a.txt")
      assert_equal "B", File.read(tmpdir / "b.txt")
      assert Dir.exist?(tmpdir / "subdir")
    end
  end
end
