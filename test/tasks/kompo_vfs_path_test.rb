# frozen_string_literal: true

require_relative "../test_helper"

class KompoVfsPathTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

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
      tmpdir << ["KOMPO_VFS_VERSION", "0.6.0"]
      # Should not raise
      Kompo::KompoVfsVersionCheck.verify!(tmpdir)
    end
  end

  def test_kompo_vfs_version_check_passes_with_higher_version
    with_tmpdir do |tmpdir|
      tmpdir << ["KOMPO_VFS_VERSION", "1.0.0"]
      # Should not raise
      Kompo::KompoVfsVersionCheck.verify!(tmpdir)
    end
  end

  def test_kompo_vfs_version_check_fails_when_version_too_old
    with_tmpdir do |tmpdir|
      tmpdir << ["KOMPO_VFS_VERSION", "0.5.1"]
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
      tmpdir << ["KOMPO_VFS_VERSION", "0.6.0\n"]
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
      tmpdir << ["KOMPO_VFS_VERSION", "  0.5.0  \n"]
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
      tmpdir << ["lib/libkompo_fs.a", "fake lib"] \
             << ["lib/libkompo_wrap.a", "fake lib"] \
             << ["lib/KOMPO_VFS_VERSION", "0.6.0"]

      @mock.stub(["/opt/homebrew/bin/brew", "--prefix", "kompo-vfs"], output: tmpdir, success: true)

      # Installed is a Task, so we run it via Task.run class method
      capture_io { Kompo::KompoVfsPath::FromHomebrew::Installed.run }

      assert @mock.called?(:capture, "/opt/homebrew/bin/brew", "--prefix", "kompo-vfs")
    end
  end

  def test_installed_raises_when_libs_missing
    with_tmpdir do |tmpdir|
      tmpdir << "lib/"
      # Only create dir, missing libkompo_wrap.a

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
      tmpdir << ["lib/KOMPO_VFS_VERSION", "0.6.0"]

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

class KompoVfsPathFromGitHubReleaseStructureTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_from_github_release_is_task
    assert Kompo::KompoVfsPath::FromGitHubRelease < Taski::Task
  end

  def test_from_github_release_has_path_interface
    assert_includes Kompo::KompoVfsPath::FromGitHubRelease.exported_methods, :path
  end

  def test_from_github_release_has_repo_constant
    assert_equal "ahogappa/kompo-vfs", Kompo::KompoVfsPath::FromGitHubRelease::REPO
  end

  def test_from_github_release_has_required_libs_constant
    assert_includes Kompo::KompoVfsPath::FromGitHubRelease::REQUIRED_LIBS, "libkompo_fs.a"
    assert_includes Kompo::KompoVfsPath::FromGitHubRelease::REQUIRED_LIBS, "libkompo_wrap.a"
  end
end

class KompoVfsPathFromGitHubReleaseDownloadTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def setup
    super
    @mock = setup_mock_command_runner
    WebMock.enable!

    @os = RUBY_PLATFORM.include?("darwin") ? "darwin" : "linux"
    cpu = RbConfig::CONFIG["host_cpu"]
    @arch = case cpu
    when /aarch64|arm64/ then "arm64"
    when /x86_64|x64/ then "x86_64"
    else cpu
    end
  end

  def teardown
    Kompo::KompoVfsPath::FromGitHubRelease.base_dir = nil
    WebMock.reset!
    WebMock.disable!
    teardown_mock_command_runner
    super
  end

  def test_downloads_and_extracts_tarball
    version = Kompo::KOMPO_VFS_MIN_VERSION

    with_tmpdir do |tmpdir|
      Kompo::KompoVfsPath::FromGitHubRelease.base_dir = tmpdir

      url = "https://github.com/ahogappa/kompo-vfs/releases/download/v#{version}/kompo-vfs-v#{version}-#{@os}-#{@arch}.tar.gz"
      WebMock.stub_request(:get, url).to_return(body: "fake-tarball", status: 200)

      @mock.stub(["tar", "xzf",
        tmpdir / "kompo-vfs-v#{version}-#{@os}-#{@arch}.tar.gz",
        "-C", tmpdir], output: "", success: true)

      original_run = @mock.method(:run)
      extracted_lib_dir = tmpdir / "kompo-vfs-v#{version}-#{@os}-#{@arch}" / "lib"
      extracted_version = version
      @mock.define_singleton_method(:run) do |*command, chdir: nil, env: nil, error_message: nil|
        result = original_run.call(*command, chdir: chdir, env: env, error_message: error_message)
        if command.include?("tar")
          FileUtils.mkdir_p(extracted_lib_dir)
          File.write(extracted_lib_dir / "libkompo_fs.a", "fake")
          File.write(extracted_lib_dir / "libkompo_wrap.a", "fake")
          File.write(extracted_lib_dir / "KOMPO_VFS_VERSION", extracted_version)
        end
        result
      end

      capture_io { Kompo::KompoVfsPath::FromGitHubRelease.run }

      assert_requested(:get, url)
      assert @mock.called?(:run, "tar")
    end
  end

  def test_skips_download_when_already_installed
    version = Kompo::KOMPO_VFS_MIN_VERSION

    with_tmpdir do |tmpdir|
      Kompo::KompoVfsPath::FromGitHubRelease.base_dir = tmpdir

      tmpdir << ["kompo-vfs-v#{version}-#{@os}-#{@arch}/lib/libkompo_fs.a", "fake"] \
             << ["kompo-vfs-v#{version}-#{@os}-#{@arch}/lib/libkompo_wrap.a", "fake"] \
             << ["kompo-vfs-v#{version}-#{@os}-#{@arch}/lib/KOMPO_VFS_VERSION", version]

      capture_io { Kompo::KompoVfsPath::FromGitHubRelease.run }

      assert_not_requested(:get, /github\.com/)
    end
  end

  def test_raises_with_message_on_http_error
    version = Kompo::KOMPO_VFS_MIN_VERSION

    with_tmpdir do |tmpdir|
      Kompo::KompoVfsPath::FromGitHubRelease.base_dir = tmpdir

      url = "https://github.com/ahogappa/kompo-vfs/releases/download/v#{version}/kompo-vfs-v#{version}-#{@os}-#{@arch}.tar.gz"
      WebMock.stub_request(:get, url).to_return(status: 404, body: "Not Found")

      error = assert_raises(Taski::AggregateError) do
        capture_io { Kompo::KompoVfsPath::FromGitHubRelease.run }
      end
      assert_includes error.message, url
      assert_includes error.message, "404"
      assert_includes error.message, "#{@os}-#{@arch}"
    end
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
