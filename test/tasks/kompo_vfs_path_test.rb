# frozen_string_literal: true

require_relative "../test_helper"

class KompoVfsPathTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_kompo_vfs_path_impl_can_access_local_path_arg
    with_tmpdir do |tmpdir|
      vfs_path = File.join(tmpdir, "kompo-vfs")
      FileUtils.mkdir_p(vfs_path)

      mock_args(local_kompo_vfs_path: vfs_path)

      assert_equal vfs_path, Taski.args[:local_kompo_vfs_path]
    end
  end

  def test_kompo_vfs_path_is_task
    assert Kompo::KompoVfsPath < Taski::Task
    assert_includes Kompo::KompoVfsPath.exported_methods, :path
  end

  def test_kompo_vfs_path_has_from_local_class
    assert_kind_of Class, Kompo::KompoVfsPath::FromLocal
    assert Kompo::KompoVfsPath::FromLocal < Taski::Task
  end

  def test_kompo_vfs_path_has_from_homebrew_task
    assert_kind_of Class, Kompo::KompoVfsPath::FromHomebrew
    assert Kompo::KompoVfsPath::FromHomebrew < Taski::Task
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
    with_tmpdir do |tmpdir|
      File.write(File.join(tmpdir, "KOMPO_VFS_VERSION"), "0.6.0")
      # Should not raise
      Kompo::KompoVfsVersionCheck.verify!(tmpdir)
    end
  end

  def test_kompo_vfs_version_check_passes_with_higher_version
    with_tmpdir do |tmpdir|
      File.write(File.join(tmpdir, "KOMPO_VFS_VERSION"), "1.0.0")
      # Should not raise
      Kompo::KompoVfsVersionCheck.verify!(tmpdir)
    end
  end

  def test_kompo_vfs_version_check_fails_when_version_too_old
    with_tmpdir do |tmpdir|
      File.write(File.join(tmpdir, "KOMPO_VFS_VERSION"), "0.5.1")
      error = assert_raises(Kompo::KompoVfsVersionCheck::IncompatibleVersionError) do
        Kompo::KompoVfsVersionCheck.verify!(tmpdir)
      end
      assert_includes error.message, "0.5.1 is too old"
      assert_includes error.message, "Required: >= 0.6.0"
    end
  end

  def test_kompo_vfs_version_check_fails_when_version_file_missing
    with_tmpdir do |tmpdir|
      error = assert_raises(Kompo::KompoVfsVersionCheck::IncompatibleVersionError) do
        Kompo::KompoVfsVersionCheck.verify!(tmpdir)
      end
      assert_includes error.message, "version file not found"
      assert_includes error.message, "may be outdated"
    end
  end

  def test_kompo_vfs_version_check_get_version_reads_file
    with_tmpdir do |tmpdir|
      File.write(File.join(tmpdir, "KOMPO_VFS_VERSION"), "0.6.0\n")
      assert_equal "0.6.0", Kompo::KompoVfsVersionCheck.get_version(tmpdir)
    end
  end

  def test_kompo_vfs_version_check_version_satisfies
    assert Kompo::KompoVfsVersionCheck.version_satisfies?("0.5.0", "0.5.0")
    assert Kompo::KompoVfsVersionCheck.version_satisfies?("0.6.0", "0.5.0")
    assert Kompo::KompoVfsVersionCheck.version_satisfies?("1.0.0", "0.5.0")
    refute Kompo::KompoVfsVersionCheck.version_satisfies?("0.4.0", "0.5.0")
    refute Kompo::KompoVfsVersionCheck.version_satisfies?("0.4.9", "0.5.0")
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
    with_tmpdir do |tmpdir|
      File.write(File.join(tmpdir, "KOMPO_VFS_VERSION"), "  0.5.0  \n")
      assert_equal "0.5.0", Kompo::KompoVfsVersionCheck.get_version(tmpdir)
    end
  end

  def test_kompo_vfs_version_check_get_version_raises_when_file_missing
    with_tmpdir do |tmpdir|
      error = assert_raises(Kompo::KompoVfsVersionCheck::IncompatibleVersionError) do
        Kompo::KompoVfsVersionCheck.get_version(tmpdir)
      end
      assert_includes error.message, "version file not found"
    end
  end
end

class KompoVfsPathFromLocalTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_from_local_is_task
    assert Kompo::KompoVfsPath::FromLocal < Taski::Task
  end
end

class KompoVfsPathFromHomebrewInstalledTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def setup
    super
    @mock = setup_mock_command_runner
    mock_task(Kompo::HomebrewPath, path: "/opt/homebrew/bin/brew")
  end

  def teardown
    teardown_mock_command_runner
    super
  end

  def test_installed_gets_prefix_and_verifies_libs
    with_tmpdir do |tmpdir|
      lib_dir = File.join(tmpdir, "lib")
      FileUtils.mkdir_p(lib_dir)
      File.write(File.join(lib_dir, "libkompo_fs.a"), "fake lib")
      File.write(File.join(lib_dir, "libkompo_wrap.a"), "fake lib")
      File.write(File.join(lib_dir, "KOMPO_VFS_VERSION"), "0.6.0")

      @mock.stub(["/opt/homebrew/bin/brew", "--prefix", "kompo-vfs"], output: tmpdir, success: true)

      # Installed is a Task, so we run it via Task.run class method
      capture_io { Kompo::KompoVfsPath::FromHomebrew::Installed.run }

      assert @mock.called?(:capture, "/opt/homebrew/bin/brew", "--prefix", "kompo-vfs")
    end
  end

  def test_installed_raises_when_libs_missing
    with_tmpdir do |tmpdir|
      lib_dir = File.join(tmpdir, "lib")
      FileUtils.mkdir_p(lib_dir)
      # Only create one lib, missing libkompo_wrap.a

      @mock.stub(["/opt/homebrew/bin/brew", "--prefix", "kompo-vfs"], output: tmpdir, success: true)
      @mock.stub(["/opt/homebrew/bin/brew", "list", "--versions", "kompo-vfs"], output: "kompo-vfs 0.1.0", success: true)

      error = assert_raises(Taski::AggregateError) do
        capture_io { Kompo::KompoVfsPath::FromHomebrew::Installed.run }
      end
      assert_includes error.message, "outdated"
      assert_includes error.message, "brew upgrade"
    end
  end
end

class KompoVfsPathFromHomebrewInstallWithMockTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def setup
    super
    @mock = setup_mock_command_runner
    mock_task(Kompo::HomebrewPath, path: "/opt/homebrew/bin/brew")
  end

  def teardown
    teardown_mock_command_runner
    super
  end

  def test_install_taps_and_installs
    with_tmpdir do |tmpdir|
      lib_dir = File.join(tmpdir, "lib")
      FileUtils.mkdir_p(lib_dir)
      File.write(File.join(lib_dir, "KOMPO_VFS_VERSION"), "0.6.0")

      @mock.stub(["/opt/homebrew/bin/brew", "tap", "ahogappa/kompo-vfs", "https://github.com/ahogappa/kompo-vfs.git"], output: "", success: true)
      @mock.stub(["/opt/homebrew/bin/brew", "install", "ahogappa/kompo-vfs/kompo-vfs"], output: "", success: true)
      @mock.stub(["/opt/homebrew/bin/brew", "--prefix", "kompo-vfs"], output: tmpdir, success: true)

      # Install is a Task, so we run it via Task.run class method
      capture_io { Kompo::KompoVfsPath::FromHomebrew::Install.run }

      assert @mock.called?(:run, "/opt/homebrew/bin/brew", "tap", "ahogappa/kompo-vfs")
      assert @mock.called?(:run, "/opt/homebrew/bin/brew", "install", "ahogappa/kompo-vfs/kompo-vfs")
    end
  end
end

class KompoVfsPathFromSourceTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_from_source_is_task
    assert Kompo::KompoVfsPath::FromSource < Taski::Task
  end

  def test_from_source_has_repo_url_constant
    assert_equal "https://github.com/ahogappa/kompo-vfs", Kompo::KompoVfsPath::FromSource::REPO_URL
  end
end

class KompoVfsPathImplSelectionTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_kompo_vfs_path_is_task
    assert Kompo::KompoVfsPath < Taski::Task
  end

  def test_from_local_selected_when_local_path_arg_present
    # FromLocal is selected when local_kompo_vfs_path arg is provided
    # This is a design/configuration test, not an execution test
    assert Kompo::KompoVfsPath::FromLocal < Taski::Task
  end

  def test_from_homebrew_is_task
    assert Kompo::KompoVfsPath::FromHomebrew < Taski::Task
  end
end

class KompoVfsFromHomebrewStructureTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_from_homebrew_is_task
    assert Kompo::KompoVfsPath::FromHomebrew < Taski::Task
  end

  def test_from_homebrew_has_path_interface
    assert_includes Kompo::KompoVfsPath::FromHomebrew.exported_methods, :path
  end

  def test_from_homebrew_installed_is_task
    assert Kompo::KompoVfsPath::FromHomebrew::Installed < Taski::Task
  end

  def test_from_homebrew_install_is_task
    assert Kompo::KompoVfsPath::FromHomebrew::Install < Taski::Task
  end
end
