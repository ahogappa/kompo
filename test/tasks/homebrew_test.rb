# frozen_string_literal: true

require_relative "../test_helper"

class HomebrewPathStructureTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_homebrew_path_task_has_path_interface
    assert Kompo::HomebrewPath < Taski::Task
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
    # Calling .path triggers Task execution and returns the exported value
    capture_io { path = Kompo::HomebrewPath.path }

    # Verify Task returns valid path via exports
    assert_equal "/opt/homebrew/bin/brew", path
  end

  def test_returns_valid_path_when_brew_in_common_paths
    # which returns nil, but File.executable? returns true for common path
    # Root Fiber runs first: homebrew_installed? → true, then Installed.run
    executable_mock = ::Minitest::Mock.new
    executable_mock.expect(:call, true, [String])   # homebrew_installed? first path check (found)
    executable_mock.expect(:call, true, [String])   # Installed.run first path check (found)

    path = nil
    File.stub(:executable?, executable_mock) do
      # Calling .path triggers Task execution and returns the exported value
      capture_io { path = Kompo::HomebrewPath.path }
    end

    # Verify Task returns valid path via exports
    assert_includes ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"], path
    executable_mock.verify
  end

  def test_returns_valid_path_after_installation
    # Root Fiber runs first: homebrew_installed? → false, then Install.run
    executable_mock = ::Minitest::Mock.new
    executable_mock.expect(:call, false, [String])  # homebrew_installed? first path
    executable_mock.expect(:call, false, [String])  # homebrew_installed? second path
    executable_mock.expect(:call, true, [String])   # Install.run: found at first path after install

    path = nil
    File.stub(:executable?, executable_mock) do
      # Calling .path triggers Task execution and returns the exported value
      capture_io { path = Kompo::HomebrewPath.path }
    end

    # Verify Task returns valid path via exports
    assert_includes ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"], path
    executable_mock.verify
  end
end
