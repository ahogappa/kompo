# frozen_string_literal: true

require_relative "../test_helper"

class RubyBuildPathStructureTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_ruby_build_path_is_section
    assert Kompo::RubyBuildPath < Taski::Section
  end

  def test_ruby_build_path_has_path_interface
    assert_includes Kompo::RubyBuildPath.exported_methods, :path
  end
end

class RubyBuildPathTest < Minitest::Test
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

  def test_returns_valid_path_when_ruby_build_in_path
    @mock.stub(["ruby-build"], output: "/usr/local/bin/ruby-build")
    @mock.stub(["/usr/local/bin/ruby-build", "--version"], output: "ruby-build 20240101")

    path = nil
    # Calling .path triggers Section execution and returns the interface value
    capture_io { path = Kompo::RubyBuildPath.path }

    assert_equal "/usr/local/bin/ruby-build", path
  end

  def test_returns_valid_path_on_darwin_when_ruby_build_not_in_path
    skip unless RUBY_PLATFORM.include?("darwin")

    # ruby-build not in PATH, Homebrew is available
    mock_task(Kompo::HomebrewPath, path: "/opt/homebrew/bin/brew")

    @mock.stub(["/opt/homebrew/bin/brew", "install", "ruby-build"], output: "", success: true)
    @mock.stub(["/opt/homebrew/bin/brew", "--prefix", "ruby-build"], output: "/opt/homebrew/opt/ruby-build")
    @mock.stub(["/opt/homebrew/opt/ruby-build/bin/ruby-build", "--version"], output: "ruby-build 20240501")

    executable_mock = ::Minitest::Mock.new
    # check_homebrew_available! checks brew paths
    executable_mock.expect(:call, true, [String])
    # FromHomebrew.run checks installed ruby-build
    executable_mock.expect(:call, true, ["/opt/homebrew/opt/ruby-build/bin/ruby-build"])

    path = nil
    File.stub(:executable?, executable_mock) do
      # Calling .path triggers Section execution and returns the interface value
      capture_io { path = Kompo::RubyBuildPath.path }
    end

    # Verify Section returns valid path via interface
    assert_equal "/opt/homebrew/opt/ruby-build/bin/ruby-build", path
    executable_mock.verify
  end

  def test_returns_valid_path_on_linux_when_ruby_build_not_in_path
    skip if RUBY_PLATFORM.include?("darwin")

    install_dir = File.expand_path("~/.ruby-build")
    ruby_build_bin = File.join(install_dir, "bin", "ruby-build")

    @mock.stub(["git", "clone", "https://github.com/rbenv/ruby-build.git", install_dir],
      output: "", success: true)
    @mock.stub([ruby_build_bin, "--version"], output: "ruby-build 20240501")

    executable_mock = ::Minitest::Mock.new
    executable_mock.expect(:call, true, [ruby_build_bin])

    path = nil
    Dir.stub(:exist?, false, [install_dir]) do
      File.stub(:executable?, executable_mock) do
        # Calling .path triggers Section execution and returns the interface value
        capture_io { path = Kompo::RubyBuildPath.path }
      end
    end

    # Verify Section returns valid path via interface
    assert_equal ruby_build_bin, path
    executable_mock.verify
  end
end
