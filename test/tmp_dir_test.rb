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
      assert File.exist?(File.join(tmpdir, "empty.txt"))
      assert_equal "", File.read(File.join(tmpdir, "empty.txt"))
    end
  end

  def test_shovel_array_creates_file_with_content
    with_tmpdir do |tmpdir|
      tmpdir << ["hello.txt", "hello world"]
      assert_equal "hello world", File.read(File.join(tmpdir, "hello.txt"))
    end
  end

  def test_shovel_string_with_trailing_slash_creates_directory
    with_tmpdir do |tmpdir|
      tmpdir << "subdir/"
      assert Dir.exist?(File.join(tmpdir, "subdir"))
    end
  end

  def test_shovel_nested_path_creates_parent_dirs
    with_tmpdir do |tmpdir|
      tmpdir << ["deep/nested/file.txt", "content"]
      assert_equal "content", File.read(File.join(tmpdir, "deep/nested/file.txt"))
    end
  end

  def test_shovel_nested_empty_file_creates_parent_dirs
    with_tmpdir do |tmpdir|
      tmpdir << "deep/nested/empty.txt"
      assert File.exist?(File.join(tmpdir, "deep/nested/empty.txt"))
    end
  end

  def test_shovel_nested_directory_creates_full_path
    with_tmpdir do |tmpdir|
      tmpdir << "a/b/c/"
      assert Dir.exist?(File.join(tmpdir, "a/b/c"))
    end
  end

  def test_shovel_single_element_array_creates_empty_file
    with_tmpdir do |tmpdir|
      tmpdir << ["empty.txt"]
      assert File.exist?(File.join(tmpdir, "empty.txt"))
      assert_equal "", File.read(File.join(tmpdir, "empty.txt"))
    end
  end

  def test_shovel_single_element_array_with_trailing_slash_creates_directory
    with_tmpdir do |tmpdir|
      tmpdir << ["subdir/"]
      assert Dir.exist?(File.join(tmpdir, "subdir"))
    end
  end

  def test_shovel_single_element_array_with_nested_path_creates_parent_dirs
    with_tmpdir do |tmpdir|
      tmpdir << ["deep/nested/empty.txt"]
      assert File.exist?(File.join(tmpdir, "deep/nested/empty.txt"))
    end
  end

  def test_shovel_array_with_three_or_more_elements_raises_error
    with_tmpdir do |tmpdir|
      assert_raises(ArgumentError) { tmpdir << ["a.txt", "content", "extra"] }
    end
  end

  def test_shovel_returns_self_for_chaining
    with_tmpdir do |tmpdir|
      tmpdir << "a.txt" << ["b.txt", "B"] << "subdir/"
      assert File.exist?(File.join(tmpdir, "a.txt"))
      assert_equal "B", File.read(File.join(tmpdir, "b.txt"))
      assert Dir.exist?(File.join(tmpdir, "subdir"))
    end
  end
end
