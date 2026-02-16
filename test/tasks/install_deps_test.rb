# frozen_string_literal: true

require_relative "../test_helper"

class InstallDepsTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_install_deps_is_task
    assert Kompo::InstallDeps < Taski::Task
  end

  def test_install_deps_has_lib_paths_interface
    assert_includes Kompo::InstallDeps.exported_methods, :lib_paths
  end

  def test_install_deps_has_static_libs_interface
    assert_includes Kompo::InstallDeps.exported_methods, :static_libs
  end

  def test_install_deps_has_for_macos_implementation
    assert_kind_of Class, Kompo::InstallDeps::ForMacOS
    assert Kompo::InstallDeps::ForMacOS < Taski::Task
  end

  def test_install_deps_has_for_linux_implementation
    assert_kind_of Class, Kompo::InstallDeps::ForLinux
    assert Kompo::InstallDeps::ForLinux < Taski::Task
  end

  def test_for_macos_has_packages_constant
    assert_kind_of Hash, Kompo::InstallDeps::ForMacOS::PACKAGES
    assert Kompo::InstallDeps::ForMacOS::PACKAGES.key?(:gmp)
    assert Kompo::InstallDeps::ForMacOS::PACKAGES.key?(:openssl)
    assert Kompo::InstallDeps::ForMacOS::PACKAGES.key?(:readline)
    assert Kompo::InstallDeps::ForMacOS::PACKAGES.key?(:libyaml)
    assert Kompo::InstallDeps::ForMacOS::PACKAGES.key?(:zlib)
    assert Kompo::InstallDeps::ForMacOS::PACKAGES.key?(:libffi)
    assert Kompo::InstallDeps::ForMacOS::PACKAGES.key?(:xz)
  end

  def test_for_macos_packages_are_brew_packages
    Kompo::InstallDeps::ForMacOS::PACKAGES.each_value do |package|
      assert_kind_of Kompo::BrewPackage, package
    end
  end

  def test_install_deps_for_linux_has_required_libs_constant
    assert_kind_of Hash, Kompo::InstallDeps::ForLinux::REQUIRED_LIBS
    assert Kompo::InstallDeps::ForLinux::REQUIRED_LIBS.key?("openssl")
    assert Kompo::InstallDeps::ForLinux::REQUIRED_LIBS.key?("readline")
    assert Kompo::InstallDeps::ForLinux::REQUIRED_LIBS.key?("zlib")
    assert Kompo::InstallDeps::ForLinux::REQUIRED_LIBS.key?("libyaml")
    assert Kompo::InstallDeps::ForLinux::REQUIRED_LIBS.key?("libffi")
  end

  def test_install_deps_for_linux_required_libs_have_pkg_config_names
    Kompo::InstallDeps::ForLinux::REQUIRED_LIBS.each do |name, info|
      assert info.key?(:pkg_config), "#{name} should have pkg_config key"
      assert info.key?(:apt), "#{name} should have apt key"
      assert info.key?(:yum), "#{name} should have yum key"
    end
  end
end
