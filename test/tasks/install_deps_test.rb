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

  def test_install_deps_has_for_macos_class
    assert_kind_of Class, Kompo::InstallDeps::ForMacOS
    assert Kompo::InstallDeps::ForMacOS < Taski::Task
  end

  def test_install_deps_has_for_linux_class
    assert_kind_of Class, Kompo::InstallDeps::ForLinux
    assert Kompo::InstallDeps::ForLinux < Taski::Task
  end
end

class InstallDepsForMacOSStructureTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_for_macos_has_gmp_section
    assert_kind_of Class, Kompo::InstallDeps::ForMacOS::InstallGmp
    assert Kompo::InstallDeps::ForMacOS::InstallGmp < Taski::Section
  end

  def test_for_macos_has_openssl_section
    assert_kind_of Class, Kompo::InstallDeps::ForMacOS::InstallOpenssl
    assert Kompo::InstallDeps::ForMacOS::InstallOpenssl < Taski::Section
  end

  def test_for_macos_has_readline_section
    assert_kind_of Class, Kompo::InstallDeps::ForMacOS::InstallReadline
    assert Kompo::InstallDeps::ForMacOS::InstallReadline < Taski::Section
  end

  def test_for_macos_has_libyaml_section
    assert_kind_of Class, Kompo::InstallDeps::ForMacOS::InstallLibyaml
    assert Kompo::InstallDeps::ForMacOS::InstallLibyaml < Taski::Section
  end

  def test_for_macos_has_zlib_section
    assert_kind_of Class, Kompo::InstallDeps::ForMacOS::InstallZlib
    assert Kompo::InstallDeps::ForMacOS::InstallZlib < Taski::Section
  end

  def test_for_macos_has_libffi_section
    assert_kind_of Class, Kompo::InstallDeps::ForMacOS::InstallLibffi
    assert Kompo::InstallDeps::ForMacOS::InstallLibffi < Taski::Section
  end

  def test_for_macos_has_xz_section
    assert_kind_of Class, Kompo::InstallDeps::ForMacOS::InstallXz
    assert Kompo::InstallDeps::ForMacOS::InstallXz < Taski::Section
  end
end

class InstallGmpStructureTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_install_gmp_is_section
    assert Kompo::InstallDeps::ForMacOS::InstallGmp < Taski::Section
  end

  def test_install_gmp_installed_is_task
    assert Kompo::InstallDeps::ForMacOS::InstallGmp::Installed < Taski::Task
  end

  def test_install_gmp_install_is_task
    assert Kompo::InstallDeps::ForMacOS::InstallGmp::Install < Taski::Task
  end

  def test_install_gmp_has_lib_path_export
    assert_includes Kompo::InstallDeps::ForMacOS::InstallGmp.exported_methods, :lib_path
  end
end

class InstallGmpInstallCleanTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def setup
    super
    @mock = setup_mock_command_runner
    @marker_file = Kompo::InstallDeps::ForMacOS::InstallGmp::MARKER_FILE
    mock_task(Kompo::HomebrewPath, path: "/opt/homebrew/bin/brew")
    File.delete(@marker_file) if File.exist?(@marker_file)
  end

  def teardown
    teardown_mock_command_runner
    File.delete(@marker_file) if File.exist?(@marker_file)
    super
  end

  def test_clean_uninstalls_when_marker_exists
    File.write(@marker_file, "installed")
    @mock.stub(["/opt/homebrew/bin/brew", "uninstall", "gmp"], output: "", success: true)

    task = Kompo::InstallDeps::ForMacOS::InstallGmp::Install.new
    task.clean

    assert @mock.called?(:run, "/opt/homebrew/bin/brew", "uninstall", "gmp")
    refute File.exist?(@marker_file)
  end

  def test_clean_does_nothing_when_marker_not_exists
    task = Kompo::InstallDeps::ForMacOS::InstallGmp::Install.new
    task.clean

    refute @mock.called?(:run, "/opt/homebrew/bin/brew", "uninstall")
  end
end

class InstallDepsForLinuxStructureTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_for_linux_is_task
    assert Kompo::InstallDeps::ForLinux < Taski::Task
  end

  def test_for_linux_is_implementation_of_install_deps_section
    # ForLinux is a Task implementation selected by InstallDeps Section.
    # When the Section runs, it applies the interface (lib_paths, static_libs)
    # to the implementation via apply_interface_to_implementation.
    # Here we just verify the class hierarchy.
    assert Kompo::InstallDeps::ForLinux < Taski::Task
    refute Kompo::InstallDeps::ForLinux < Taski::Section
  end

  def test_for_linux_required_libs_constant
    required_libs = Kompo::InstallDeps::ForLinux::REQUIRED_LIBS

    assert_includes required_libs.keys, "openssl"
    assert_includes required_libs.keys, "readline"
    assert_includes required_libs.keys, "zlib"
    assert_includes required_libs.keys, "libyaml"
    assert_includes required_libs.keys, "libffi"
    assert_includes required_libs.keys, "gmp"
    assert_includes required_libs.keys, "liblzma"

    # gmp and liblzma should be optional
    assert required_libs["gmp"][:optional]
    assert required_libs["liblzma"][:optional]
  end
end
