# frozen_string_literal: true

require_relative "../test_helper"

class HomebrewPathStructureTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_homebrew_path_section_has_path_interface
    assert Kompo::HomebrewPath < Taski::Section
    assert_includes Kompo::HomebrewPath.exported_methods, :path
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

  def test_returns_valid_path_when_brew_in_path
    @mock.stub(["brew"], output: "/opt/homebrew/bin/brew")

    path = nil
    # Calling .path triggers Section execution and returns the interface value
    capture_io { path = Kompo::HomebrewPath.path }

    # Verify Section returns valid path via interface
    assert_equal "/opt/homebrew/bin/brew", path
  end

  def test_returns_valid_path_when_brew_in_common_paths
    # which returns nil, but File.executable? returns true for common path
    executable_mock = ::Minitest::Mock.new
    executable_mock.expect(:call, false, [String])  # homebrew_installed? first path check
    executable_mock.expect(:call, true, [String])   # homebrew_installed? second path check (found)
    executable_mock.expect(:call, true, [String])   # Installed.run fallback check

    path = nil
    File.stub(:executable?, executable_mock) do
      # Calling .path triggers Section execution and returns the interface value
      capture_io { path = Kompo::HomebrewPath.path }
    end

    # Verify Section returns valid path via interface
    assert_includes ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"], path
    executable_mock.verify
  end

  def test_returns_valid_path_after_installation
    # which returns nil and File.executable? returns false, then true after install
    executable_mock = ::Minitest::Mock.new
    executable_mock.expect(:call, false, [String])  # homebrew_installed? first path
    executable_mock.expect(:call, false, [String])  # homebrew_installed? second path
    executable_mock.expect(:call, true, [String])   # Install.run check after install

    path = nil
    File.stub(:executable?, executable_mock) do
      # Calling .path triggers Section execution and returns the interface value
      capture_io { path = Kompo::HomebrewPath.path }
    end

    # Verify Section returns valid path via interface
    assert_includes ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"], path
    executable_mock.verify
  end
end
