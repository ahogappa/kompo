# frozen_string_literal: true

require_relative "../test_helper"

class DependencyInstallTasksTest < Minitest::Test
  # These are nested inside InstallDeps::ForMacOS as independent Sections
  INSTALL_SECTIONS = [
    Kompo::InstallDeps::ForMacOS::InstallGmp,
    Kompo::InstallDeps::ForMacOS::InstallOpenssl,
    Kompo::InstallDeps::ForMacOS::InstallReadline,
    Kompo::InstallDeps::ForMacOS::InstallLibyaml,
    Kompo::InstallDeps::ForMacOS::InstallZlib,
    Kompo::InstallDeps::ForMacOS::InstallLibffi
  ].freeze

  INSTALL_SECTIONS.each do |section_class|
    class_name = section_class.name.split("::").last

    define_method("test_#{class_name.downcase}_is_section") do
      assert_kind_of Class, section_class
      assert section_class < Taski::Section, "#{section_class} should be a Section"
    end

    define_method("test_#{class_name.downcase}_has_lib_path_interface") do
      assert_includes section_class.exported_methods, :lib_path
    end

    define_method("test_#{class_name.downcase}_has_installed_and_install_implementations") do
      assert_kind_of Class, section_class::Installed
      assert_kind_of Class, section_class::Install
      assert section_class::Installed < Taski::Task
      assert section_class::Install < Taski::Task
    end

    define_method("test_#{class_name.downcase}_has_marker_file_constant") do
      assert_kind_of String, section_class::MARKER_FILE
      assert section_class::MARKER_FILE.start_with?(File.expand_path("~"))
    end

    define_method("test_#{class_name.downcase}_has_brew_name_constant") do
      assert_kind_of String, section_class::BREW_NAME
    end
  end
end

class InstallDepsTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_install_deps_is_section
    assert Kompo::InstallDeps < Taski::Section
  end

  def test_install_deps_has_for_macos_implementation
    assert_kind_of Class, Kompo::InstallDeps::ForMacOS
    assert Kompo::InstallDeps::ForMacOS < Taski::Task
  end

  def test_install_deps_has_for_linux_implementation
    assert_kind_of Class, Kompo::InstallDeps::ForLinux
    assert Kompo::InstallDeps::ForLinux < Taski::Task
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

  def test_install_deps_section_has_lib_paths_interface
    # The Section interface is defined at InstallDeps level
    exported = Kompo::InstallDeps.exported_methods
    assert_includes exported, :lib_paths
  end
end
