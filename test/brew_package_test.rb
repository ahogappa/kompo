# frozen_string_literal: true

require_relative "test_helper"

class BrewPackageTest < Minitest::Test
  include TaskTestHelpers

  def setup
    super
    @mock = setup_mock_command_runner
    @package = Kompo::BrewPackage.new(
      name: "testpkg",
      static_lib_names: %w[libtest.a],
      marker_file: File.join(Dir.tmpdir, ".kompo_test_marker")
    )
  end

  def teardown
    teardown_mock_command_runner
    File.delete(@package.marker_file) if File.exist?(@package.marker_file)
    super
  end

  def test_installed_returns_true_when_package_exists
    @mock.stub(["/brew", "list", "testpkg"], output: "", success: true)

    assert @package.installed?("/brew")
  end

  def test_installed_returns_false_when_package_not_exists
    @mock.stub(["/brew", "list", "testpkg"], output: "", success: false)

    refute @package.installed?("/brew")
  end

  def test_prefix_returns_path_when_available
    @mock.stub(["/brew", "--prefix", "testpkg"], output: "/opt/homebrew/opt/testpkg", success: true)

    assert_equal "/opt/homebrew/opt/testpkg", @package.prefix("/brew")
  end

  def test_prefix_returns_nil_when_not_available
    @mock.stub(["/brew", "--prefix", "testpkg"], output: "", success: false)

    assert_nil @package.prefix("/brew")
  end

  def test_lib_path_returns_flag_when_prefix_available
    @mock.stub(["/brew", "--prefix", "testpkg"], output: "/opt/testpkg", success: true)

    assert_equal "-L/opt/testpkg/lib", @package.lib_path("/brew")
  end

  def test_lib_path_returns_nil_when_prefix_not_available
    @mock.stub(["/brew", "--prefix", "testpkg"], output: "", success: false)

    assert_nil @package.lib_path("/brew")
  end

  def test_static_libs_returns_existing_files
    with_tmpdir do |tmpdir|
      tmpdir << "lib/libtest.a"
      @mock.stub(["/brew", "--prefix", "testpkg"], output: tmpdir, success: true)

      libs = @package.static_libs("/brew")

      assert_equal [File.join(tmpdir / "lib", "libtest.a")], libs
    end
  end

  def test_static_libs_returns_empty_when_prefix_not_available
    @mock.stub(["/brew", "--prefix", "testpkg"], output: "", success: false)

    assert_equal [], @package.static_libs("/brew")
  end

  def test_install_runs_brew_install
    @mock.stub(["/brew", "install", "testpkg"], output: "", success: true)

    capture_io { @package.install("/brew") }

    assert @mock.called?(:run, "/brew", "install", "testpkg")
    assert File.exist?(@package.marker_file)
  end

  def test_uninstall_runs_brew_uninstall_when_marker_exists
    # Create marker file
    File.write(@package.marker_file, "installed")

    @mock.stub(["/brew", "uninstall", "testpkg"], output: "", success: true)

    capture_io { @package.uninstall("/brew") }

    assert @mock.called?(:run, "/brew", "uninstall", "testpkg")
    refute File.exist?(@package.marker_file)
  end

  def test_uninstall_does_nothing_when_marker_not_exists
    refute File.exist?(@package.marker_file)

    @package.uninstall("/brew")

    refute @mock.called?(:run, "/brew", "uninstall", "testpkg")
  end

  def test_attributes_are_accessible
    assert_equal "testpkg", @package.name
    assert_equal %w[libtest.a], @package.static_lib_names
    assert @package.marker_file.end_with?(".kompo_test_marker")
  end
end
