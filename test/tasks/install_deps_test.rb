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

  def test_returns_lib_paths_with_mocked_dependencies
    skip unless RUBY_PLATFORM.include?("darwin")

    # Mock all internal dependency Sections
    mock_task(Kompo::InstallDeps::ForMacOS::InstallGmp, lib_path: "-L/opt/homebrew/opt/gmp/lib", static_libs: ["/opt/homebrew/opt/gmp/lib/libgmp.a"])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallOpenssl, lib_path: "-L/opt/homebrew/opt/openssl@3/lib", static_libs: ["/opt/homebrew/opt/openssl@3/lib/libssl.a"])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallReadline, lib_path: "-L/opt/homebrew/opt/readline/lib", static_libs: [])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallLibyaml, lib_path: "-L/opt/homebrew/opt/libyaml/lib", static_libs: [])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallZlib, lib_path: "-L/opt/homebrew/opt/zlib/lib", static_libs: [])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallLibffi, lib_path: "-L/opt/homebrew/opt/libffi/lib", static_libs: [])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallXz, lib_path: "-L/opt/homebrew/opt/xz/lib", static_libs: [])

    lib_paths = nil
    capture_io { lib_paths = Kompo::InstallDeps.lib_paths }

    # Verify lib_paths contains all -L flags joined
    assert_match(/-L\/opt\/homebrew\/opt\/gmp\/lib/, lib_paths)
    assert_match(/-L\/opt\/homebrew\/opt\/openssl@3\/lib/, lib_paths)
    assert_match(/-L\/opt\/homebrew\/opt\/readline\/lib/, lib_paths)
  end

  def test_returns_static_libs_with_mocked_dependencies
    skip unless RUBY_PLATFORM.include?("darwin")

    # Mock all internal dependency Sections
    mock_task(Kompo::InstallDeps::ForMacOS::InstallGmp, lib_path: "-L/lib", static_libs: ["/lib/libgmp.a"])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallOpenssl, lib_path: "-L/lib", static_libs: ["/lib/libssl.a", "/lib/libcrypto.a"])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallReadline, lib_path: "-L/lib", static_libs: ["/lib/libreadline.a"])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallLibyaml, lib_path: "-L/lib", static_libs: ["/lib/libyaml.a"])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallZlib, lib_path: "-L/lib", static_libs: ["/lib/libz.a"])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallLibffi, lib_path: "-L/lib", static_libs: ["/lib/libffi.a"])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallXz, lib_path: "-L/lib", static_libs: ["/lib/liblzma.a"])

    static_libs = nil
    capture_io { static_libs = Kompo::InstallDeps.static_libs }

    # Verify static_libs is array containing all static lib paths
    assert_kind_of Array, static_libs
    assert_includes static_libs, "/lib/libgmp.a"
    assert_includes static_libs, "/lib/libssl.a"
    assert_includes static_libs, "/lib/libcrypto.a"
    assert_equal 8, static_libs.size
  end

  def test_handles_nil_lib_path
    skip unless RUBY_PLATFORM.include?("darwin")

    # Some packages might not have lib_path (nil case)
    mock_task(Kompo::InstallDeps::ForMacOS::InstallGmp, lib_path: nil, static_libs: [])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallOpenssl, lib_path: "-L/lib", static_libs: [])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallReadline, lib_path: nil, static_libs: [])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallLibyaml, lib_path: nil, static_libs: [])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallZlib, lib_path: nil, static_libs: [])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallLibffi, lib_path: nil, static_libs: [])
    mock_task(Kompo::InstallDeps::ForMacOS::InstallXz, lib_path: nil, static_libs: [])

    lib_paths = nil
    capture_io { lib_paths = Kompo::InstallDeps.lib_paths }

    # Verify only non-nil paths are included
    assert_equal "-L/lib", lib_paths
  end
end

class InstallGmpTest < Minitest::Test
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

  def test_installed_returns_lib_path_when_package_exists
    skip unless RUBY_PLATFORM.include?("darwin")

    mock_task(Kompo::HomebrewPath, path: "/opt/homebrew/bin/brew")

    # Package is installed
    @mock.stub(["/opt/homebrew/bin/brew", "list", "gmp"], output: "", success: true)
    @mock.stub(["/opt/homebrew/bin/brew", "--prefix", "gmp"], output: "/opt/homebrew/opt/gmp")

    lib_path = nil
    capture_io { lib_path = Kompo::InstallDeps::ForMacOS::InstallGmp.lib_path }

    assert_equal "-L/opt/homebrew/opt/gmp/lib", lib_path
  end

  def test_installed_returns_static_libs_when_files_exist
    skip unless RUBY_PLATFORM.include?("darwin")

    mock_task(Kompo::HomebrewPath, path: "/opt/homebrew/bin/brew")

    Dir.mktmpdir do |tmpdir|
      lib_dir = File.join(tmpdir, "lib")
      FileUtils.mkdir_p(lib_dir)
      FileUtils.touch(File.join(lib_dir, "libgmp.a"))

      @mock.stub(["/opt/homebrew/bin/brew", "list", "gmp"], output: "", success: true)
      @mock.stub(["/opt/homebrew/bin/brew", "--prefix", "gmp"], output: tmpdir)

      static_libs = nil
      capture_io { static_libs = Kompo::InstallDeps::ForMacOS::InstallGmp.static_libs }

      assert_equal [File.join(lib_dir, "libgmp.a")], static_libs
    end
  end

  def test_install_runs_brew_install_when_package_not_installed
    skip unless RUBY_PLATFORM.include?("darwin")

    mock_task(Kompo::HomebrewPath, path: "/opt/homebrew/bin/brew")

    marker_file = Kompo::InstallDeps::ForMacOS::InstallGmp::MARKER_FILE
    File.delete(marker_file) if File.exist?(marker_file)

    begin
      # Package is not installed
      @mock.stub(["/opt/homebrew/bin/brew", "list", "gmp"], output: "", success: false)
      @mock.stub(["/opt/homebrew/bin/brew", "install", "gmp"], output: "", success: true)
      @mock.stub(["/opt/homebrew/bin/brew", "--prefix", "gmp"], output: "/opt/homebrew/opt/gmp")

      lib_path = nil
      capture_io { lib_path = Kompo::InstallDeps::ForMacOS::InstallGmp.lib_path }

      assert @mock.called?(:run, "/opt/homebrew/bin/brew", "install", "gmp")
      assert_equal "-L/opt/homebrew/opt/gmp/lib", lib_path
    ensure
      File.delete(marker_file) if File.exist?(marker_file)
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
