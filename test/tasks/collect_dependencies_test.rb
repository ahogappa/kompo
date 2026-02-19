# frozen_string_literal: true

require_relative "../test_helper"

class CollectDependenciesTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_collect_dependencies_output_path_in_directory
    with_tmpdir do |tmpdir|
      tmpdir << "work/" << "myproject/" << "output/"
      work_dir = tmpdir / "work"
      project_dir = tmpdir / "myproject"
      output_dir = tmpdir / "output"

      # Mock all dependencies
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::InstallRuby,
        ruby_install_dir: "/path/to/install",
        ruby_version: "3.4.1",
        ruby_major_minor: "3.4",
        ruby_build_path: "/path/to/build")
      mock_task(Kompo::KompoVfsPath, path: "/path/to/kompo_lib")
      mock_task(Kompo::MakeMainC, path: File.join(work_dir, "main.c"))
      mock_task(Kompo::MakeFsC, path: File.join(work_dir, "fs.c"))
      mock_task(Kompo::BuildNativeGem, exts_dir: nil, exts: [])
      mock_task(Kompo::InstallDeps, lib_paths: "", static_libs: [])
      output_path = Kompo::CollectDependencies.output_path(args: {project_dir: project_dir, output_dir: output_dir})

      # Output should be in output_dir with project name
      assert_equal File.join(output_dir, "myproject"), output_path
    end
  end

  def test_collect_dependencies_output_path_as_file
    with_tmpdir do |tmpdir|
      tmpdir << "work/" << "myproject/"
      work_dir = tmpdir / "work"
      project_dir = tmpdir / "myproject"
      output_file = tmpdir / "mybinary"

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::InstallRuby,
        ruby_install_dir: "/path/to/install",
        ruby_version: "3.4.1",
        ruby_major_minor: "3.4",
        ruby_build_path: "/path/to/build")
      mock_task(Kompo::KompoVfsPath, path: "/path/to/kompo_lib")
      mock_task(Kompo::MakeMainC, path: File.join(work_dir, "main.c"))
      mock_task(Kompo::MakeFsC, path: File.join(work_dir, "fs.c"))
      mock_task(Kompo::BuildNativeGem, exts_dir: nil, exts: [])
      mock_task(Kompo::InstallDeps, lib_paths: "", static_libs: [])
      output_path = Kompo::CollectDependencies.output_path(args: {project_dir: project_dir, output_dir: output_file})

      # Output should be the specified file path
      assert_equal output_file, output_path
    end
  end

  def test_collect_dependencies_collects_all_dependencies
    with_tmpdir do |tmpdir|
      tmpdir << "work/" << "myproject/" << "output/"
      work_dir = tmpdir / "work"
      project_dir = tmpdir / "myproject"
      output_dir = tmpdir / "output"

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::InstallRuby,
        ruby_install_dir: "/test/install",
        ruby_version: "3.4.1",
        ruby_major_minor: "3.4",
        ruby_build_path: "/test/build")
      mock_task(Kompo::KompoVfsPath, path: "/test/kompo_lib")
      mock_task(Kompo::MakeMainC, path: "/test/main.c")
      mock_task(Kompo::MakeFsC, path: "/test/fs.c")
      mock_task(Kompo::BuildNativeGem, exts_dir: "/test/exts", exts: ["ext1"])
      mock_task(Kompo::InstallDeps, lib_paths: "", static_libs: [])
      # Access deps through exported value
      deps = Kompo::CollectDependencies.deps(args: {project_dir: project_dir, output_dir: output_dir})

      # Verify all dependencies were collected
      assert_equal "/test/install", deps.ruby_install_dir
      assert_equal "3.4.1", deps.ruby_version
      assert_equal "3.4", deps.ruby_major_minor
      assert_equal "/test/build", deps.ruby_build_path
      assert_equal "/test/kompo_lib", deps.kompo_lib
      assert_equal "/test/main.c", deps.main_c
      assert_equal "/test/fs.c", deps.fs_c
      assert_equal "/test/exts", deps.exts_dir

      # Verify dependent tasks were accessed
      assert_task_accessed(Kompo::InstallRuby, :ruby_install_dir)
      assert_task_accessed(Kompo::KompoVfsPath, :path)
      assert_task_accessed(Kompo::MakeMainC, :path)
      assert_task_accessed(Kompo::MakeFsC, :path)
      assert_task_accessed(Kompo::BuildNativeGem, :exts_dir)
    end
  end
end
