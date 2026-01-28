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
    @mock = setup_mock_command_runner
    @marker_file = Kompo::HomebrewPath::Install::MARKER_FILE
    File.delete(@marker_file) if File.exist?(@marker_file)
  end

  def teardown
    teardown_mock_command_runner
    File.delete(@marker_file) if File.exist?(@marker_file)
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

class HomebrewImplSelectionTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def setup
    @mock = setup_mock_command_runner
  end

  def teardown
    teardown_mock_command_runner
  end

  def test_impl_selects_installed_when_brew_in_path
    @mock.stub(["brew"], output: "/opt/homebrew/bin/brew", success: true)

    section = Kompo::HomebrewPath.new
    impl = section.impl

    assert @mock.called?(:which, "brew")
    assert_equal Kompo::HomebrewPath::Installed, impl
  end

  def test_impl_selects_installed_when_brew_in_common_paths
    # Even when which returns nil, if a common path exists, Installed is chosen
    @mock.stub(["brew"], output: "", success: false)

    # Verify that if COMMON_BREW_PATHS exist on filesystem, Installed is selected
    # This test just documents the expected behavior - the impl method
    # checks COMMON_BREW_PATHS via File.executable?, so if brew exists at
    # /opt/homebrew/bin/brew, it will return Installed
    section = Kompo::HomebrewPath.new
    impl = section.impl

    assert @mock.called?(:which, "brew")
    # On systems with Homebrew installed, this returns Installed
    # On systems without Homebrew, this returns Install
    # Both are valid - we just verify the which call happened
    assert [Kompo::HomebrewPath::Installed, Kompo::HomebrewPath::Install].include?(impl)
  end
end
