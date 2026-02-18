# frozen_string_literal: true

require_relative "../test_helper"

class MakeMainCTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_main_c_escapes_backslash_in_paths
    with_tmpdir do |tmpdir|
      tmpdir << "work/"
      work_dir = File.join(tmpdir, "work")

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyProjectFiles, entrypoint_path: 'path\to\main.rb')
      mock_task(Kompo::BuildNativeGem, exts: [])
      mock_task(Kompo::CopyGemfile, gemfile_exists: false)
      mock_args(project_dir: File.join(tmpdir, "project"))

      Kompo::MakeMainC.run
      content = File.read(File.join(work_dir, "main.c"))

      assert_includes content, 'path\\\\to\\\\main.rb'
      refute_includes content, 'path\to\main.rb'
    end
  end

  def test_main_c_escapes_double_quotes_in_paths
    with_tmpdir do |tmpdir|
      tmpdir << "work/" << ['project "app"/.keep', ""]
      work_dir = File.join(tmpdir, "work")
      project_dir = File.join(tmpdir, 'project "app"')

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyProjectFiles, entrypoint_path: "/tmp/main.rb")
      mock_task(Kompo::BuildNativeGem, exts: [])
      mock_task(Kompo::CopyGemfile, gemfile_exists: false)
      mock_args(project_dir: project_dir)

      Kompo::MakeMainC.run
      content = File.read(File.join(work_dir, "main.c"))

      assert_includes content, 'project \\"app\\"'
    end
  end

  def test_main_c_removes_nul_from_paths
    with_tmpdir do |tmpdir|
      tmpdir << "work/"
      work_dir = File.join(tmpdir, "work")

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyProjectFiles, entrypoint_path: "cle\0an.rb")
      mock_task(Kompo::BuildNativeGem, exts: [])
      mock_task(Kompo::CopyGemfile, gemfile_exists: false)
      mock_args(project_dir: File.join(tmpdir, "project"))

      Kompo::MakeMainC.run
      content = File.read(File.join(work_dir, "main.c"))

      assert_includes content, "clean.rb"
      refute_includes content, "\0"
    end
  end

  def test_main_c_normal_path_unchanged
    with_tmpdir do |tmpdir|
      tmpdir << "work/"
      work_dir = File.join(tmpdir, "work")

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyProjectFiles, entrypoint_path: "/tmp/kompo-work/main.rb")
      mock_task(Kompo::BuildNativeGem, exts: [])
      mock_task(Kompo::CopyGemfile, gemfile_exists: false)
      mock_args(project_dir: File.join(tmpdir, "project"))

      Kompo::MakeMainC.run
      content = File.read(File.join(work_dir, "main.c"))

      assert_includes content, "/tmp/kompo-work/main.rb"
    end
  end
end
