# frozen_string_literal: true

require_relative "../test_helper"

class KompoVfsPathTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_kompo_vfs_path_impl_can_access_local_path_arg
    Dir.mktmpdir do |tmpdir|
      vfs_path = File.join(tmpdir, "kompo-vfs")
      FileUtils.mkdir_p(vfs_path)

      mock_args(local_kompo_vfs_path: vfs_path)

      assert_equal vfs_path, Taski.args[:local_kompo_vfs_path]
    end
  end

  def test_kompo_vfs_path_selects_from_local_when_arg_set
    Dir.mktmpdir do |tmpdir|
      vfs_path = File.join(tmpdir, "kompo-vfs")
      target_dir = File.join(vfs_path, "target", "release")
      FileUtils.mkdir_p(target_dir)
      # Create VERSION file for version check
      File.write(File.join(target_dir, "KOMPO_VFS_VERSION"), Kompo::KOMPO_VFS_MIN_VERSION)

      mock_task(Kompo::CargoPath, path: "/usr/bin/cargo")
      mock_args(local_kompo_vfs_path: vfs_path)

      # Stub the system call to avoid actual build
      Kompo::KompoVfsPath::FromLocal.define_method(:system) do |*_args, **_kwargs|
        true
      end

      begin
        path = Kompo::KompoVfsPath.path
        assert_equal target_dir, path
      ensure
        Kompo::KompoVfsPath::FromLocal.remove_method(:system)
      end
    end
  end

  def test_kompo_vfs_path_is_section
    assert Kompo::KompoVfsPath < Taski::Section
    assert_includes Kompo::KompoVfsPath.exported_methods, :path
  end

  def test_kompo_vfs_path_has_from_local_class
    assert_kind_of Class, Kompo::KompoVfsPath::FromLocal
    assert Kompo::KompoVfsPath::FromLocal < Taski::Task
  end

  def test_kompo_vfs_path_has_from_homebrew_section
    assert_kind_of Class, Kompo::KompoVfsPath::FromHomebrew
    assert Kompo::KompoVfsPath::FromHomebrew < Taski::Section
  end

  def test_kompo_vfs_path_has_from_source_class
    assert_kind_of Class, Kompo::KompoVfsPath::FromSource
    assert Kompo::KompoVfsPath::FromSource < Taski::Task
  end

  def test_kompo_vfs_path_from_source_has_repo_url
    assert_equal "https://github.com/ahogappa/kompo-vfs", Kompo::KompoVfsPath::FromSource::REPO_URL
  end

  def test_kompo_vfs_path_from_homebrew_has_implementations
    assert_kind_of Class, Kompo::KompoVfsPath::FromHomebrew::Installed
    assert_kind_of Class, Kompo::KompoVfsPath::FromHomebrew::Install
  end

  def test_kompo_vfs_version_check_passes_when_version_satisfies
    Dir.mktmpdir do |tmpdir|
      File.write(File.join(tmpdir, "KOMPO_VFS_VERSION"), "0.5.1")
      # Should not raise
      Kompo::KompoVfsVersionCheck.verify!(tmpdir)
    end
  end

  def test_kompo_vfs_version_check_passes_with_higher_version
    Dir.mktmpdir do |tmpdir|
      File.write(File.join(tmpdir, "KOMPO_VFS_VERSION"), "1.0.0")
      # Should not raise
      Kompo::KompoVfsVersionCheck.verify!(tmpdir)
    end
  end

  def test_kompo_vfs_version_check_fails_when_version_too_old
    Dir.mktmpdir do |tmpdir|
      File.write(File.join(tmpdir, "KOMPO_VFS_VERSION"), "0.4.0")
      error = assert_raises(Kompo::KompoVfsVersionCheck::IncompatibleVersionError) do
        Kompo::KompoVfsVersionCheck.verify!(tmpdir)
      end
      assert_includes error.message, "0.4.0 is too old"
      assert_includes error.message, "Required: >= 0.5.1"
    end
  end

  def test_kompo_vfs_version_check_fails_when_version_file_missing
    Dir.mktmpdir do |tmpdir|
      error = assert_raises(Kompo::KompoVfsVersionCheck::IncompatibleVersionError) do
        Kompo::KompoVfsVersionCheck.verify!(tmpdir)
      end
      assert_includes error.message, "version file not found"
      assert_includes error.message, "may be outdated"
    end
  end

  def test_kompo_vfs_version_check_get_version_reads_file
    Dir.mktmpdir do |tmpdir|
      File.write(File.join(tmpdir, "KOMPO_VFS_VERSION"), "0.5.1\n")
      assert_equal "0.5.1", Kompo::KompoVfsVersionCheck.get_version(tmpdir)
    end
  end

  def test_kompo_vfs_version_check_version_satisfies
    assert Kompo::KompoVfsVersionCheck.version_satisfies?("0.5.0", "0.5.0")
    assert Kompo::KompoVfsVersionCheck.version_satisfies?("0.6.0", "0.5.0")
    assert Kompo::KompoVfsVersionCheck.version_satisfies?("1.0.0", "0.5.0")
    refute Kompo::KompoVfsVersionCheck.version_satisfies?("0.4.0", "0.5.0")
    refute Kompo::KompoVfsVersionCheck.version_satisfies?("0.4.9", "0.5.0")
  end

  def test_kompo_vfs_path_from_source_has_repo_url_constant
    assert_equal "https://github.com/ahogappa/kompo-vfs", Kompo::KompoVfsPath::FromSource::REPO_URL
  end

  def test_kompo_vfs_path_from_homebrew_installed_class_exists
    assert_kind_of Class, Kompo::KompoVfsPath::FromHomebrew::Installed
    assert Kompo::KompoVfsPath::FromHomebrew::Installed < Taski::Task
  end

  def test_kompo_vfs_path_from_homebrew_install_class_exists
    assert_kind_of Class, Kompo::KompoVfsPath::FromHomebrew::Install
    assert Kompo::KompoVfsPath::FromHomebrew::Install < Taski::Task
  end

  def test_kompo_vfs_version_check_get_version_strips_whitespace
    Dir.mktmpdir do |tmpdir|
      File.write(File.join(tmpdir, "KOMPO_VFS_VERSION"), "  0.5.0  \n")
      assert_equal "0.5.0", Kompo::KompoVfsVersionCheck.get_version(tmpdir)
    end
  end

  def test_kompo_vfs_version_check_get_version_raises_when_file_missing
    Dir.mktmpdir do |tmpdir|
      error = assert_raises(Kompo::KompoVfsVersionCheck::IncompatibleVersionError) do
        Kompo::KompoVfsVersionCheck.get_version(tmpdir)
      end
      assert_includes error.message, "version file not found"
    end
  end
end
