# frozen_string_literal: true

require_relative "../test_helper"

class PackingTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_packing_is_section
    assert Kompo::Packing < Taski::Section
  end

  def test_packing_has_for_macos_implementation
    assert_kind_of Class, Kompo::Packing::ForMacOS
    assert Kompo::Packing::ForMacOS < Taski::Task
  end

  def test_packing_has_for_linux_implementation
    assert_kind_of Class, Kompo::Packing::ForLinux
    assert Kompo::Packing::ForLinux < Taski::Task
  end

  def test_packing_for_macos_has_system_libs_constant
    assert_kind_of Array, Kompo::Packing::ForMacOS::SYSTEM_LIBS
    assert_includes Kompo::Packing::ForMacOS::SYSTEM_LIBS, "pthread"
    assert_includes Kompo::Packing::ForMacOS::SYSTEM_LIBS, "m"
    assert_includes Kompo::Packing::ForMacOS::SYSTEM_LIBS, "c"
  end

  def test_packing_for_macos_has_frameworks_constant
    assert_kind_of Array, Kompo::Packing::ForMacOS::FRAMEWORKS
    assert_includes Kompo::Packing::ForMacOS::FRAMEWORKS, "Foundation"
    assert_includes Kompo::Packing::ForMacOS::FRAMEWORKS, "CoreFoundation"
    assert_includes Kompo::Packing::ForMacOS::FRAMEWORKS, "Security"
  end

  def test_packing_for_linux_has_dyn_link_libs_constant
    assert_kind_of Array, Kompo::Packing::ForLinux::DYN_LINK_LIBS
    assert_includes Kompo::Packing::ForLinux::DYN_LINK_LIBS, "pthread"
    assert_includes Kompo::Packing::ForLinux::DYN_LINK_LIBS, "dl"
    assert_includes Kompo::Packing::ForLinux::DYN_LINK_LIBS, "m"
    assert_includes Kompo::Packing::ForLinux::DYN_LINK_LIBS, "c"
  end

  def test_common_helpers_module_exists
    assert_kind_of Module, Kompo::Packing::CommonHelpers
  end

  def test_for_macos_includes_common_helpers
    assert Kompo::Packing::ForMacOS.include?(Kompo::Packing::CommonHelpers)
  end

  def test_for_linux_includes_common_helpers
    assert Kompo::Packing::ForLinux.include?(Kompo::Packing::CommonHelpers)
  end
end
