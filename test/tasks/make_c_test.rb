# frozen_string_literal: true

require_relative '../test_helper'

class MakeMainCTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_make_main_c_generates_file
    Dir.mktmpdir do |tmpdir|
      work_dir = File.join(tmpdir, 'work')
      FileUtils.mkdir_p(work_dir)
      main_c_path = File.join(work_dir, 'main.c')
      entrypoint = File.join(work_dir, 'main.rb')

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyProjectFiles, entrypoint_path: entrypoint, additional_paths: [])
      mock_task(Kompo::BuildNativeGem, exts: [], exts_dir: nil)
      mock_task(Kompo::CopyGemfile, gemfile_exists: false)
      mock_task(Kompo::FindNativeExtensions, extensions: [])
      mock_task(Kompo::InstallRuby,
                ruby_version: '3.4.1',
                ruby_build_path: '/path/to/build',
                ruby_path: '/path/to/ruby',
                ruby_install_dir: '/path/to/install',
                original_ruby_install_dir: '/path/to/install',
                ruby_major_minor: '3.4')
      mock_task(Kompo::BundleInstall,
                bundle_ruby_dir: nil,
                bundler_config_path: nil)

      path = Kompo::MakeMainC.path

      assert_equal main_c_path, path
      assert File.exist?(main_c_path), 'main.c should be generated'
      content = File.read(main_c_path)
      assert_includes content, 'ruby_init'
    end
  end
end

class MakeFsCTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_make_fs_c_generates_file
    Dir.mktmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint)

      path = Kompo::MakeFsC.path

      assert_equal File.join(work_dir, 'fs.c'), path
      assert File.exist?(path), 'fs.c should be generated'
      content = File.read(path)
      assert_includes content, 'const char FILES[]'
      assert_includes content, 'const char PATHS[]'
    end
  end

  def test_make_fs_c_with_additional_paths
    Dir.mktmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      lib_dir = File.join(work_dir, 'lib')
      FileUtils.mkdir_p(lib_dir)
      File.write(File.join(lib_dir, 'app.rb'), 'class App; end')

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint, additional_paths: [lib_dir])

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
      assert_includes File.read(path), 'const char FILES[]'
    end
  end

  def test_make_fs_c_prunes_git_directories
    Dir.mktmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      lib_dir = File.join(work_dir, 'lib')
      git_dir = File.join(lib_dir, '.git')
      FileUtils.mkdir_p([lib_dir, git_dir])
      File.write(File.join(lib_dir, 'app.rb'), 'class App; end')
      File.write(File.join(git_dir, 'config'), 'git config')

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint, additional_paths: [lib_dir])

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
      refute_includes File.read(path), 'git config'
    end
  end

  def test_make_fs_c_handles_nonexistent_path
    Dir.mktmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint, additional_paths: ['/nonexistent/path'])

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
    end
  end

  def test_make_fs_c_skips_binary_extensions
    Dir.mktmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      File.write(File.join(work_dir, 'test.so'), 'binary')
      File.write(File.join(work_dir, 'test.o'), 'object')
      File.write(File.join(work_dir, 'image.png'), 'image')

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint)

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
    end
  end

  def test_make_fs_c_with_gemfile
    Dir.mktmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir, content: "require 'bundler/setup'")
      bundle_dir = File.join(work_dir, 'bundle', 'ruby', '3.4.0')
      bundle_config_dir = File.join(work_dir, '.bundle')
      FileUtils.mkdir_p([bundle_dir, bundle_config_dir])
      File.write(File.join(work_dir, 'Gemfile'), "source 'https://rubygems.org'")
      File.write(File.join(work_dir, 'Gemfile.lock'), "GEM\n  specs:\n")
      File.write(File.join(bundle_config_dir, 'config'), 'BUNDLE_PATH: bundle')

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint,
                             gemfile_exists: true,
                             bundler_config_path: File.join(bundle_config_dir, 'config'),
                             bundle_ruby_dir: bundle_dir)

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
    end
  end

  def test_make_fs_c_with_kompoignore
    Dir.mktmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      project_dir = File.join(tmpdir, 'project')
      FileUtils.mkdir_p(project_dir)
      File.write(File.join(project_dir, '.kompoignore'), "*.log\ntmp/")

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint)
      mock_args(project_dir: project_dir)

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
    end
  end

  def test_make_fs_c_ignores_files_matching_kompoignore
    Dir.mktmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      project_dir = File.join(tmpdir, 'project')
      tmp_dir = File.join(work_dir, 'tmp')
      FileUtils.mkdir_p([project_dir, tmp_dir])
      File.write(File.join(work_dir, 'debug.log'), 'DEBUG LOG CONTENT')
      File.write(File.join(tmp_dir, 'cache.txt'), 'TEMP CACHE CONTENT')
      File.write(File.join(project_dir, '.kompoignore'), "*.log\ntmp/")

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint)
      mock_args(project_dir: project_dir)

      path = Kompo::MakeFsC.path
      content = File.read(path)
      paths_match = content.match(/const char PATHS\[\] = \{([^}]+)\}/)
      assert paths_match, 'Should have PATHS array'
      decoded_paths = paths_match[1].split(',').map(&:to_i).pack('C*')
      refute_includes decoded_paths, 'debug.log'
      refute_includes decoded_paths, 'cache.txt'
      assert_includes decoded_paths, 'main.rb'
    end
  end

  def test_make_fs_c_skips_symlinks_escaping_base_directory
    Dir.mktmpdir do |tmpdir|
      # Resolve tmpdir to real path (macOS /var -> /private/var symlink)
      tmpdir = File.realpath(tmpdir)

      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      lib_dir = File.join(work_dir, 'lib')
      FileUtils.mkdir_p(lib_dir)
      File.write(File.join(lib_dir, 'app.rb'), 'class App; end')

      # Create a directory outside work_dir
      outside_dir = File.join(tmpdir, 'outside')
      FileUtils.mkdir_p(outside_dir)
      File.write(File.join(outside_dir, 'secret.rb'), 'SECRET_DATA')

      # Create a symlink in lib_dir pointing to outside_dir
      symlink_path = File.join(lib_dir, 'external_link')
      File.symlink(outside_dir, symlink_path)

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint, additional_paths: [lib_dir])

      path = Kompo::MakeFsC.path

      # Verify fs.c was generated
      assert File.exist?(path)
      content = File.read(path)

      # The symlink target content should NOT be included
      refute_includes content, 'SECRET_DATA'

      # Regular file should still be included
      paths_match = content.match(/const char PATHS\[\] = \{([^}]+)\}/)
      assert paths_match, 'Should have PATHS array'
      decoded_paths = paths_match[1].split(',').map(&:to_i).pack('C*')
      assert_includes decoded_paths, 'app.rb'
    end
  end

  def test_make_fs_c_allows_symlinks_within_base_directory
    Dir.mktmpdir do |tmpdir|
      # Resolve tmpdir to real path (macOS /var -> /private/var symlink)
      tmpdir = File.realpath(tmpdir)

      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      lib_dir = File.join(work_dir, 'lib')
      real_dir = File.join(lib_dir, 'real')
      FileUtils.mkdir_p(real_dir)
      File.write(File.join(real_dir, 'internal.rb'), 'INTERNAL_CONTENT')

      # Create a symlink within the same base directory
      symlink_path = File.join(lib_dir, 'linked.rb')
      File.symlink(File.join(real_dir, 'internal.rb'), symlink_path)

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint, additional_paths: [lib_dir])

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
      content = File.read(path)

      # Internal symlink content should be included
      paths_match = content.match(/const char PATHS\[\] = \{([^}]+)\}/)
      assert paths_match, 'Should have PATHS array'
      decoded_paths = paths_match[1].split(',').map(&:to_i).pack('C*')
      assert_includes decoded_paths, 'internal.rb'
    end
  end

  def test_make_fs_c_handles_binary_content_correctly
    Dir.mktmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)

      # Create a directory with a binary file
      lib_dir = File.join(work_dir, 'lib')
      FileUtils.mkdir_p(lib_dir)

      # Create a file with binary content (non-UTF8 bytes)
      binary_content = "\x00\x01\x02\xFF\xFE\xFD"
      binary_file = File.join(lib_dir, 'binary.dat.rb') # Use .rb extension to not be skipped
      File.binwrite(binary_file, binary_content)

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint, additional_paths: [lib_dir])

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
      content = File.read(path)

      # The binary bytes should be embedded in FILES array
      # Binary content: \x00\x01\x02\xFF\xFE\xFD = 0, 1, 2, 255, 254, 253
      assert_includes content, '0,1,2,255,254,253'
    end
  end

  private

  def setup_work_dir_with_entrypoint(tmpdir, content: "puts 'hello'")
    work_dir = File.join(tmpdir, 'work')
    FileUtils.mkdir_p(work_dir)
    entrypoint = File.join(work_dir, 'main.rb')
    File.write(entrypoint, content)
    [work_dir, entrypoint]
  end

  def mock_fs_c_dependencies(work_dir, tmpdir, entrypoint,
                             additional_paths: [],
                             gemfile_exists: false,
                             gemspec_paths: [],
                             bundler_config_path: nil,
                             bundle_ruby_dir: nil)
    mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
    mock_task(Kompo::InstallRuby,
              ruby_install_dir: '/path/to/install',
              original_ruby_install_dir: '/path/to/install',
              ruby_major_minor: '3.4')
    mock_task(Kompo::CopyProjectFiles, entrypoint_path: entrypoint, additional_paths: additional_paths)
    mock_task(Kompo::CopyGemfile, gemfile_exists: gemfile_exists, gemspec_paths: gemspec_paths)
    mock_task(Kompo::BundleInstall, bundler_config_path: bundler_config_path, bundle_ruby_dir: bundle_ruby_dir)
    mock_task(Kompo::CheckStdlibs, paths: [])
  end
end
