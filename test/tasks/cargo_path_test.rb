# frozen_string_literal: true

require_relative "../test_helper"

class CargoPathTest < Minitest::Test
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
    @mock.stub(["cargo"], output: "/usr/local/bin/cargo")

    capture_io { Kompo::CargoPath.run }

    assert @mock.called?(:which, "cargo")
    assert @mock.called?(:capture_all, "/usr/local/bin/cargo", "--version")
  end

  def test_uses_install_when_cargo_not_found
    executable_mock = ::Minitest::Mock.new
    # Root Fiber runs first: cargo_installed? → false, then Install.run executes
    executable_mock.expect(:call, false, [String])  # cargo_installed? check (root Fiber)
    executable_mock.expect(:call, true, [String])   # Install.run: check after install

    File.stub(:executable?, executable_mock) do
      capture_io { Kompo::CargoPath.run }

      assert @mock.called?(:which, "cargo")
      assert @mock.called?(:run, "/bin/sh", "-c")
      assert @mock.called?(:capture_all, File.expand_path("~/.cargo/bin/cargo"), "--version")
    end
    executable_mock.verify
  end
end
