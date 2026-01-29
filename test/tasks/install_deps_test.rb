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
