# frozen_string_literal: true

require_relative "../test_helper"

class HomebrewPathStructureTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_homebrew_path_section_has_path_interface
    assert Kompo::HomebrewPath < Taski::Section
    assert_includes Kompo::HomebrewPath.exported_methods, :path
  end

  def test_homebrew_path_has_installed_class
    assert_kind_of Class, Kompo::HomebrewPath::Installed
    assert Kompo::HomebrewPath::Installed < Taski::Task
  end

  def test_homebrew_path_has_install_class
    assert_kind_of Class, Kompo::HomebrewPath::Install
    assert Kompo::HomebrewPath::Install < Taski::Task
  end

  def test_common_brew_paths_constant
    assert_equal ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"], Kompo::HomebrewPath::COMMON_BREW_PATHS
  end

  def test_install_marker_file_constant
    assert_includes Kompo::HomebrewPath::Install::MARKER_FILE, ".kompo_installed_homebrew"
  end

  def test_install_script_url_constant
    assert_includes Kompo::HomebrewPath::Install::INSTALL_SCRIPT_URL, "Homebrew/install"
  end
end

class HomebrewPathInstallCleanTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def setup
    super
    @mock = setup_mock_command_runner
    @marker_file = Kompo::HomebrewPath::Install::MARKER_FILE
    File.delete(@marker_file) if File.exist?(@marker_file)
  end

  def teardown
    teardown_mock_command_runner
    File.delete(@marker_file) if File.exist?(@marker_file)
    super
  end

  def test_clean_uninstalls_when_marker_exists
    File.write(@marker_file, "/opt/homebrew/bin/brew")
    @mock.stub(["/bin/bash", "-c", "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"], output: "", success: true)

    task = Kompo::HomebrewPath::Install.new
    task.clean

    assert @mock.called?(:run, "/bin/bash", "-c")
    refute File.exist?(@marker_file)
  end

  def test_clean_does_nothing_when_marker_not_exists
    refute File.exist?(@marker_file)

    task = Kompo::HomebrewPath::Install.new
    task.clean

    refute @mock.called?(:run, "/bin/bash")
  end
end

class HomebrewPathTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def setup
    super
    @mock = setup_mock_command_runner
  end

  def teardown
    teardown_mock_command_runner
    super
  end

  def test_uses_installed_when_which_returns_path
    @mock.stub(["brew"], output: "/opt/homebrew/bin/brew")

    capture_io { Kompo::HomebrewPath.run }

    assert @mock.called?(:which, "brew")
  end

  def test_uses_installed_when_brew_in_common_paths
    # which returns nil, but File.executable? returns true for common path
    executable_mock = ::Minitest::Mock.new
    executable_mock.expect(:call, false, [String])  # homebrew_installed? first path check
    executable_mock.expect(:call, true, [String])   # homebrew_installed? second path check (found)
    executable_mock.expect(:call, true, [String])   # Installed.run fallback check

    File.stub(:executable?, executable_mock) do
      capture_io { Kompo::HomebrewPath.run }

      assert @mock.called?(:which, "brew")
    end
    executable_mock.verify
  end

  def test_uses_install_when_brew_not_found
    # which returns nil and File.executable? returns false, then true after install
    executable_mock = ::Minitest::Mock.new
    executable_mock.expect(:call, false, [String])  # homebrew_installed? first path
    executable_mock.expect(:call, false, [String])  # homebrew_installed? second path
    executable_mock.expect(:call, true, [String])   # Install.run check after install

    File.stub(:executable?, executable_mock) do
      capture_io { Kompo::HomebrewPath.run }

      assert @mock.called?(:which, "brew")
      assert @mock.called?(:run, "/bin/bash", "-c")
    end
    executable_mock.verify
  end
end
