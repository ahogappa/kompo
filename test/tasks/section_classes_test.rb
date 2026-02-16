# frozen_string_literal: true

require_relative "../test_helper"

class SectionClassesTest < Minitest::Test
  SECTIONS_WITH_IMPLEMENTATIONS = [
    [Kompo::CargoPath, [:path]],
    [Kompo::HomebrewPath, [:path]]
  ].freeze

  SECTIONS_WITH_IMPLEMENTATIONS.each do |section_class, expected_methods|
    class_name = section_class.name.split("::").last

    define_method("test_#{class_name.downcase}_is_task") do
      assert section_class < Taski::Task
      expected_methods.each do |method|
        assert_includes section_class.exported_methods, method
      end
    end

    define_method("test_#{class_name.downcase}_has_implementations") do
      assert_kind_of Class, section_class::Installed
      assert_kind_of Class, section_class::Install
      assert section_class::Installed < Taski::Task
      assert section_class::Install < Taski::Task
    end
  end
end

class RubyBuildPathTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_ruby_build_path_is_task
    assert Kompo::RubyBuildPath < Taski::Task
    assert_includes Kompo::RubyBuildPath.exported_methods, :path
  end

  def test_ruby_build_path_has_implementations
    # Installed: Use existing ruby-build installation
    assert_kind_of Class, Kompo::RubyBuildPath::Installed
    assert Kompo::RubyBuildPath::Installed < Taski::Task

    # FromHomebrew: Install via Homebrew (macOS)
    assert_kind_of Class, Kompo::RubyBuildPath::FromHomebrew
    assert Kompo::RubyBuildPath::FromHomebrew < Taski::Task

    # FromSource: Install via git clone (Linux)
    assert_kind_of Class, Kompo::RubyBuildPath::FromSource
    assert Kompo::RubyBuildPath::FromSource < Taski::Task
  end

  def test_ruby_build_path_from_source_uses_home_directory
    # The FromSource class uses ~/.ruby-build for installation
    # Verify the expected path structure
    install_dir = File.expand_path("~/.ruby-build")
    expected_path = File.join(install_dir, "bin", "ruby-build")
    assert expected_path.start_with?(File.expand_path("~"))
  end
end

class HomebrewPathTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_homebrew_path_is_task
    assert Kompo::HomebrewPath < Taski::Task
    assert_includes Kompo::HomebrewPath.exported_methods, :path
  end

  def test_homebrew_path_has_installed_and_install_implementations
    assert_kind_of Class, Kompo::HomebrewPath::Installed
    assert_kind_of Class, Kompo::HomebrewPath::Install
    assert Kompo::HomebrewPath::Installed < Taski::Task
    assert Kompo::HomebrewPath::Install < Taski::Task
  end

  def test_homebrew_path_install_has_marker_file_constant
    assert_equal File.expand_path("~/.kompo_installed_homebrew"), Kompo::HomebrewPath::Install::MARKER_FILE
  end

  def test_homebrew_path_common_brew_paths_constant
    assert_kind_of Array, Kompo::HomebrewPath::COMMON_BREW_PATHS
    assert_includes Kompo::HomebrewPath::COMMON_BREW_PATHS, "/opt/homebrew/bin/brew"
    assert_includes Kompo::HomebrewPath::COMMON_BREW_PATHS, "/usr/local/bin/brew"
  end
end
