# frozen_string_literal: true

require_relative "../test_helper"

class CopyGemfileTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_copy_gemfile_returns_false_when_no_gemfile
    with_tmpdir do |tmpdir|
      tmpdir << "work/" << "project/"
      # No Gemfile in project_dir

      mock_task(Kompo::WorkDir, path: tmpdir / "work", original_dir: tmpdir)

      refute Kompo::CopyGemfile.gemfile_exists(args: {project_dir: tmpdir / "project"})
    end
  end

  def test_copy_gemfile_returns_true_when_gemfile_exists
    with_tmpdir do |tmpdir|
      tmpdir << "work/" << ["project/Gemfile", "source 'https://rubygems.org'"]

      work_dir = tmpdir / "work"
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)

      assert Kompo::CopyGemfile.gemfile_exists(args: {project_dir: tmpdir / "project"})
      # Verify Gemfile was copied to work_dir
      assert File.exist?(work_dir / "Gemfile")
    end
  end

  def test_copy_gemfile_also_copies_gemfile_lock
    with_tmpdir do |tmpdir|
      tmpdir << "work/" \
             << ["project/Gemfile", "source 'https://rubygems.org'"] \
             << ["project/Gemfile.lock", "GEM\n  remote: https://rubygems.org/\n"]

      work_dir = tmpdir / "work"
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)

      assert Kompo::CopyGemfile.gemfile_exists(args: {project_dir: tmpdir / "project"})
      # Verify both files were copied to work_dir
      assert File.exist?(work_dir / "Gemfile")
      assert File.exist?(work_dir / "Gemfile.lock")
    end
  end

  def test_copy_gemfile_copies_gemspec_when_gemfile_references_gemspec
    with_tmpdir do |tmpdir|
      tmpdir << "work/" \
             << ["project/Gemfile", "source 'https://rubygems.org'\ngemspec"] \
             << ["project/my_gem.gemspec", "Gem::Specification.new { |s| s.name = 'my_gem' }"]

      work_dir = tmpdir / "work"
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)

      assert Kompo::CopyGemfile.gemfile_exists(args: {project_dir: tmpdir / "project"})
      # Verify Gemfile and gemspec were copied to work_dir
      assert File.exist?(work_dir / "Gemfile")
      assert File.exist?(work_dir / "my_gem.gemspec")
    end
  end

  def test_copy_gemfile_does_not_copy_gemspec_when_no_gemspec_directive
    with_tmpdir do |tmpdir|
      tmpdir << "work/" \
             << ["project/Gemfile", "source 'https://rubygems.org'\ngem 'rake'"] \
             << ["project/my_gem.gemspec", "Gem::Specification.new { |s| s.name = 'my_gem' }"]

      work_dir = tmpdir / "work"
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)

      assert Kompo::CopyGemfile.gemfile_exists(args: {project_dir: tmpdir / "project"})
      # Verify Gemfile was copied but gemspec was not
      assert File.exist?(work_dir / "Gemfile")
      refute File.exist?(work_dir / "my_gem.gemspec")
    end
  end

  def test_copy_gemfile_copies_multiple_gemspecs
    with_tmpdir do |tmpdir|
      tmpdir << "work/" \
             << ["project/Gemfile", "gemspec"] \
             << ["project/my_gem.gemspec", "Gem::Specification.new { |s| s.name = 'my_gem' }"] \
             << ["project/other_gem.gemspec", "Gem::Specification.new { |s| s.name = 'other_gem' }"]

      work_dir = tmpdir / "work"
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)

      assert Kompo::CopyGemfile.gemfile_exists(args: {project_dir: tmpdir / "project"})
      # Verify all gemspecs were copied
      assert File.exist?(work_dir / "my_gem.gemspec")
      assert File.exist?(work_dir / "other_gem.gemspec")
    end
  end

  def test_copy_gemfile_skips_symlink_escaping_project_dir
    with_tmpdir do |tmpdir|
      tmpdir << "work/" \
             << "project/" \
             << "outside/"
      # Create a real Gemfile outside project_dir
      File.write(tmpdir / "outside" / "Gemfile", "source 'https://rubygems.org'")
      # Create a symlink from project_dir/Gemfile -> outside/Gemfile
      File.symlink(tmpdir / "outside" / "Gemfile", tmpdir / "project" / "Gemfile")

      work_dir = tmpdir / "work"
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)

      _out, err = capture_io do
        refute Kompo::CopyGemfile.gemfile_exists(args: {project_dir: tmpdir / "project"})
      end

      assert_match(/escap.*project directory/i, err)
      refute File.exist?(work_dir / "Gemfile")
    end
  end

  def test_copy_gemfile_skips_when_no_gemfile_option_specified
    with_tmpdir do |tmpdir|
      tmpdir << "work/" << ["project/Gemfile", "source 'https://rubygems.org'"]

      work_dir = tmpdir / "work"
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)

      args = {project_dir: tmpdir / "project", no_gemfile: true}
      # gemfile_exists should be false even though Gemfile exists
      refute Kompo::CopyGemfile.gemfile_exists(args: args)
      # Verify Gemfile was NOT copied to work_dir
      refute File.exist?(work_dir / "Gemfile")
    end
  end
end

class CopyProjectFilesTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_copy_project_files_copies_entrypoint
    with_tmpdir do |tmpdir|
      tmpdir << "work/" << ["project/main.rb", "puts 'hello'"]

      work_dir = tmpdir / "work"
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)

      args = {project_dir: tmpdir / "project", entrypoint: "main.rb", files: []}
      entrypoint_path = Kompo::CopyProjectFiles.entrypoint_path(args: args)
      additional_paths = Kompo::CopyProjectFiles.additional_paths(args: args)

      assert_equal (work_dir / "main.rb").to_s, entrypoint_path
      assert_equal [], additional_paths
      # Verify file was copied
      assert File.exist?(entrypoint_path)
      assert_equal "puts 'hello'", File.read(entrypoint_path)
    end
  end

  def test_copy_project_files_copies_additional_files
    with_tmpdir do |tmpdir|
      tmpdir << "work/" \
             << ["project/main.rb", "require_relative 'lib/app'"] \
             << ["project/lib/app.rb", "class App; end"]

      work_dir = tmpdir / "work"
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)

      args = {project_dir: tmpdir / "project", entrypoint: "main.rb", files: ["lib"]}
      entrypoint_path = Kompo::CopyProjectFiles.entrypoint_path(args: args)
      additional_paths = Kompo::CopyProjectFiles.additional_paths(args: args)

      assert_equal (work_dir / "main.rb").to_s, entrypoint_path
      assert_includes additional_paths, (work_dir / "lib").to_s
      # Verify files were copied
      assert File.exist?(work_dir / "lib" / "app.rb")
    end
  end

  def test_copy_project_files_copies_individual_files
    with_tmpdir do |tmpdir|
      tmpdir << "work/" \
             << ["project/main.rb", "require_relative 'config/settings'"] \
             << ["project/config/settings.rb", "SETTINGS = {}"]

      work_dir = tmpdir / "work"
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)

      args = {project_dir: tmpdir / "project", entrypoint: "main.rb", files: ["config/settings.rb"]}
      entrypoint_path = Kompo::CopyProjectFiles.entrypoint_path(args: args)
      additional_paths = Kompo::CopyProjectFiles.additional_paths(args: args)

      assert_equal (work_dir / "main.rb").to_s, entrypoint_path
      assert_includes additional_paths, (work_dir / "config/settings.rb").to_s
      # Verify individual file was copied with parent dir created
      assert File.exist?(work_dir / "config" / "settings.rb")
    end
  end

  def test_copy_project_files_with_dot_copies_directory_contents
    with_tmpdir do |tmpdir|
      tmpdir << "work/" \
             << ["project/main.rb", "puts 'hello'"] \
             << ["project/app.gemspec", "Gem::Specification.new { |s| s.name = 'app' }"] \
             << ["project/lib/app.rb", "class App; end"]

      work_dir = tmpdir / "work"
      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)

      args = {project_dir: tmpdir / "project", entrypoint: "main.rb", files: ["."]}
      Kompo::CopyProjectFiles.entrypoint_path(args: args)

      # Verify all files were copied directly to work_dir (not into work_dir/project/)
      assert File.exist?(work_dir / "main.rb")
      assert File.exist?(work_dir / "app.gemspec")
      assert File.exist?(work_dir / "lib" / "app.rb")
      # Ensure no nested project directory was created
      refute File.exist?(work_dir / "project")
    end
  end
end
