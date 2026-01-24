# frozen_string_literal: true

require_relative '../test_helper'

class CopyGemfileTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_copy_gemfile_returns_false_when_no_gemfile
    Dir.mktmpdir do |tmpdir|
      work_dir = File.join(tmpdir, 'work')
      project_dir = File.join(tmpdir, 'project')
      FileUtils.mkdir_p([work_dir, project_dir])
      # No Gemfile in project_dir

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_args(project_dir: project_dir)

      refute Kompo::CopyGemfile.gemfile_exists
    end
  end

  def test_copy_gemfile_returns_true_when_gemfile_exists
    Dir.mktmpdir do |tmpdir|
      work_dir = File.join(tmpdir, 'work')
      project_dir = File.join(tmpdir, 'project')
      FileUtils.mkdir_p([work_dir, project_dir])
      # Create Gemfile in project_dir
      File.write(File.join(project_dir, 'Gemfile'), "source 'https://rubygems.org'")

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_args(project_dir: project_dir)

      assert Kompo::CopyGemfile.gemfile_exists
      # Verify Gemfile was copied to work_dir
      assert File.exist?(File.join(work_dir, 'Gemfile'))
    end
  end

  def test_copy_gemfile_also_copies_gemfile_lock
    Dir.mktmpdir do |tmpdir|
      work_dir = File.join(tmpdir, 'work')
      project_dir = File.join(tmpdir, 'project')
      FileUtils.mkdir_p([work_dir, project_dir])
      # Create both Gemfile and Gemfile.lock in project_dir
      File.write(File.join(project_dir, 'Gemfile'), "source 'https://rubygems.org'")
      File.write(File.join(project_dir, 'Gemfile.lock'), "GEM\n  remote: https://rubygems.org/\n")

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_args(project_dir: project_dir)

      assert Kompo::CopyGemfile.gemfile_exists
      # Verify both files were copied to work_dir
      assert File.exist?(File.join(work_dir, 'Gemfile'))
      assert File.exist?(File.join(work_dir, 'Gemfile.lock'))
    end
  end
end

class CopyProjectFilesTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_copy_project_files_copies_entrypoint
    Dir.mktmpdir do |tmpdir|
      work_dir = File.join(tmpdir, 'work')
      project_dir = File.join(tmpdir, 'project')
      FileUtils.mkdir_p([work_dir, project_dir])

      # Create entrypoint in project_dir
      File.write(File.join(project_dir, 'main.rb'), "puts 'hello'")

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_args(project_dir: project_dir, entrypoint: 'main.rb', files: [])

      entrypoint_path = Kompo::CopyProjectFiles.entrypoint_path
      additional_paths = Kompo::CopyProjectFiles.additional_paths

      assert_equal File.join(work_dir, 'main.rb'), entrypoint_path
      assert_equal [], additional_paths
      # Verify file was copied
      assert File.exist?(entrypoint_path)
      assert_equal "puts 'hello'", File.read(entrypoint_path)
    end
  end

  def test_copy_project_files_copies_additional_files
    Dir.mktmpdir do |tmpdir|
      # Use realpath to match WorkDir behavior (resolves symlinks like /tmp -> /private/tmp on macOS)
      tmpdir = File.realpath(tmpdir)
      work_dir = File.join(tmpdir, 'work')
      project_dir = File.join(tmpdir, 'project')
      lib_dir = File.join(project_dir, 'lib')
      FileUtils.mkdir_p([work_dir, lib_dir])

      # Create files in project_dir
      File.write(File.join(project_dir, 'main.rb'), "require_relative 'lib/app'")
      File.write(File.join(lib_dir, 'app.rb'), 'class App; end')

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_args(project_dir: project_dir, entrypoint: 'main.rb', files: ['lib'])

      entrypoint_path = Kompo::CopyProjectFiles.entrypoint_path
      additional_paths = Kompo::CopyProjectFiles.additional_paths

      assert_equal File.join(work_dir, 'main.rb'), entrypoint_path
      assert_includes additional_paths, File.join(work_dir, 'lib')
      # Verify files were copied
      assert File.exist?(File.join(work_dir, 'lib', 'app.rb'))
    end
  end

  def test_copy_project_files_copies_individual_files
    Dir.mktmpdir do |tmpdir|
      # Use realpath to match WorkDir behavior (resolves symlinks like /tmp -> /private/tmp on macOS)
      tmpdir = File.realpath(tmpdir)
      work_dir = File.join(tmpdir, 'work')
      project_dir = File.join(tmpdir, 'project')
      config_dir = File.join(project_dir, 'config')
      FileUtils.mkdir_p([work_dir, config_dir])

      # Create files in project_dir (individual file, not directory)
      File.write(File.join(project_dir, 'main.rb'), "require_relative 'config/settings'")
      File.write(File.join(config_dir, 'settings.rb'), 'SETTINGS = {}')

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_args(project_dir: project_dir, entrypoint: 'main.rb', files: ['config/settings.rb'])

      entrypoint_path = Kompo::CopyProjectFiles.entrypoint_path
      additional_paths = Kompo::CopyProjectFiles.additional_paths

      assert_equal File.join(work_dir, 'main.rb'), entrypoint_path
      assert_includes additional_paths, File.join(work_dir, 'config/settings.rb')
      # Verify individual file was copied with parent dir created
      assert File.exist?(File.join(work_dir, 'config', 'settings.rb'))
    end
  end
end
