# frozen_string_literal: true

require_relative "../test_helper"

class InstallDepsStructureTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_install_deps_section_has_lib_paths_and_static_libs_interfaces
    assert Kompo::InstallDeps < Taski::Section
    assert_includes Kompo::InstallDeps.exported_methods, :lib_paths
    assert_includes Kompo::InstallDeps.exported_methods, :static_libs
  end
end

class InstallDepsForMacOSTest < Minitest::Test
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

  def test_returns_lib_paths_when_packages_installed
    skip unless RUBY_PLATFORM.include?("darwin")

    mock_task(Kompo::HomebrewPath, path: "/opt/homebrew/bin/brew")

    # Mock all packages as installed
    Kompo::InstallDeps::ForMacOS::PACKAGES.each_value do |package|
      @mock.stub(["/opt/homebrew/bin/brew", "list", package.name], output: "", success: true)
      @mock.stub(["/opt/homebrew/bin/brew", "--prefix", package.name], output: "/opt/homebrew/opt/#{package.name}")
    end

    lib_paths = nil
    capture_io { lib_paths = Kompo::InstallDeps.lib_paths }

    assert_match(/-L\/opt\/homebrew\/opt\/gmp\/lib/, lib_paths)
    assert_match(/-L\/opt\/homebrew\/opt\/openssl@3\/lib/, lib_paths)
  end

  def test_returns_static_libs_when_files_exist
    skip unless RUBY_PLATFORM.include?("darwin")

    mock_task(Kompo::HomebrewPath, path: "/opt/homebrew/bin/brew")

    Dir.mktmpdir do |tmpdir|
      # Create lib directory with static libs
      lib_dir = File.join(tmpdir, "lib")
      FileUtils.mkdir_p(lib_dir)
      FileUtils.touch(File.join(lib_dir, "libgmp.a"))
      FileUtils.touch(File.join(lib_dir, "libssl.a"))
      FileUtils.touch(File.join(lib_dir, "libcrypto.a"))

      # Mock all packages as installed, pointing to tmpdir
      Kompo::InstallDeps::ForMacOS::PACKAGES.each_value do |package|
        @mock.stub(["/opt/homebrew/bin/brew", "list", package.name], output: "", success: true)
        @mock.stub(["/opt/homebrew/bin/brew", "--prefix", package.name], output: tmpdir)
      end

      static_libs = nil
      capture_io { static_libs = Kompo::InstallDeps.static_libs }

      assert_kind_of Array, static_libs
      assert_includes static_libs, File.join(lib_dir, "libgmp.a")
      assert_includes static_libs, File.join(lib_dir, "libssl.a")
    end
  end

  def test_installs_packages_when_not_installed
    skip unless RUBY_PLATFORM.include?("darwin")

    mock_task(Kompo::HomebrewPath, path: "/opt/homebrew/bin/brew")

    # Clean up marker files before test
    Kompo::InstallDeps::ForMacOS::PACKAGES.each_value do |package|
      File.delete(package.marker_file) if File.exist?(package.marker_file)
    end

    begin
      # Mock all packages as not installed
      Kompo::InstallDeps::ForMacOS::PACKAGES.each_value do |package|
        @mock.stub(["/opt/homebrew/bin/brew", "list", package.name], output: "", success: false)
        @mock.stub(["/opt/homebrew/bin/brew", "install", package.name], output: "", success: true)
        @mock.stub(["/opt/homebrew/bin/brew", "--prefix", package.name], output: "/opt/homebrew/opt/#{package.name}")
      end

      capture_io { Kompo::InstallDeps.lib_paths }

      # Verify install was called for each package
      Kompo::InstallDeps::ForMacOS::PACKAGES.each_value do |package|
        assert @mock.called?(:run, "/opt/homebrew/bin/brew", "install", package.name),
          "Expected brew install #{package.name} to be called"
      end
    ensure
      # Clean up marker files after test
      Kompo::InstallDeps::ForMacOS::PACKAGES.each_value do |package|
        File.delete(package.marker_file) if File.exist?(package.marker_file)
      end
    end
  end

  def test_clean_uninstalls_kompo_installed_packages
    skip unless RUBY_PLATFORM.include?("darwin")

    mock_task(Kompo::HomebrewPath, path: "/opt/homebrew/bin/brew")

    # Create marker files to simulate kompo-installed packages
    test_packages = [:gmp, :openssl]
    test_packages.each do |key|
      package = Kompo::InstallDeps::ForMacOS::PACKAGES[key]
      File.write(package.marker_file, "installed")
      @mock.stub(["/opt/homebrew/bin/brew", "uninstall", package.name], output: "", success: true)
    end

    begin
      # First run to select impl, then clean
      Kompo::InstallDeps::ForMacOS::PACKAGES.each_value do |package|
        @mock.stub(["/opt/homebrew/bin/brew", "list", package.name], output: "", success: true)
        @mock.stub(["/opt/homebrew/bin/brew", "--prefix", package.name], output: "/opt/homebrew/opt/#{package.name}")
      end

      task = nil
      capture_io do
        Kompo::InstallDeps.lib_paths
        task = Kompo::InstallDeps::ForMacOS.new
        task.clean
      end

      # Verify uninstall was called for packages with marker files
      test_packages.each do |key|
        package = Kompo::InstallDeps::ForMacOS::PACKAGES[key]
        assert @mock.called?(:run, "/opt/homebrew/bin/brew", "uninstall", package.name),
          "Expected brew uninstall #{package.name} to be called"
      end
    ensure
      # Clean up marker files
      test_packages.each do |key|
        package = Kompo::InstallDeps::ForMacOS::PACKAGES[key]
        File.delete(package.marker_file) if File.exist?(package.marker_file)
      end
    end
  end
end

class InstallDepsForLinuxTest < Minitest::Test
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

  def test_returns_lib_paths_when_pkg_config_available
    skip if RUBY_PLATFORM.include?("darwin")

    # Mock pkg-config availability
    @mock.stub(["pkg-config"], output: "/usr/bin/pkg-config")

    # Mock pkg-config --exists for required libs
    required_libs = %w[openssl readline zlib yaml-0.1 libffi gmp liblzma]
    required_libs.each do |lib|
      @mock.stub(["pkg-config", "--exists", lib], output: "", success: true)
      @mock.stub(["pkg-config", "--libs-only-L", lib], output: "-L/usr/lib/x86_64-linux-gnu")
      @mock.stub(["pkg-config", "--variable=libdir", lib], output: "/usr/lib/x86_64-linux-gnu")
    end

    lib_paths = nil
    capture_io { lib_paths = Kompo::InstallDeps.lib_paths }

    assert_match(/-L\/usr\/lib/, lib_paths)
  end

  def test_returns_empty_when_pkg_config_not_available
    skip if RUBY_PLATFORM.include?("darwin")

    # Mock pkg-config not available
    @mock.stub(["pkg-config"], output: nil)

    lib_paths = nil
    static_libs = nil
    capture_io do
      lib_paths = Kompo::InstallDeps.lib_paths
      static_libs = Kompo::InstallDeps.static_libs
    end

    assert_equal "", lib_paths
    assert_equal [], static_libs
  end

  def test_raises_error_when_required_libs_missing
    skip if RUBY_PLATFORM.include?("darwin")

    # Mock pkg-config availability
    @mock.stub(["pkg-config"], output: "/usr/bin/pkg-config")

    # Mock all required libs as missing (except optional ones)
    required_libs = %w[openssl readline zlib yaml-0.1 libffi]
    required_libs.each do |lib|
      @mock.stub(["pkg-config", "--exists", lib], output: "", success: false)
    end

    # Optional libs
    @mock.stub(["pkg-config", "--exists", "gmp"], output: "", success: false)
    @mock.stub(["pkg-config", "--exists", "liblzma"], output: "", success: false)

    error = assert_raises(RuntimeError) do
      capture_io { Kompo::InstallDeps.lib_paths }
    end

    assert_match(/Missing required development libraries/, error.message)
  end
end
