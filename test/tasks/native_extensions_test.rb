# frozen_string_literal: true

require_relative "../test_helper"

class FindNativeExtensionsTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_find_native_extensions_returns_empty_when_no_gemfile
    mock_task(Kompo::CopyGemfile, gemfile_exists: false)
    mock_standard_ruby
    mock_task(Kompo::BundleInstall, bundle_ruby_dir: "/path/to/bundle")

    extensions = Kompo::FindNativeExtensions.extensions

    assert_equal [], extensions
    assert_task_accessed(Kompo::CopyGemfile, :gemfile_exists)
  end

  def test_find_native_extensions_finds_c_extensions
    Dir.mktmpdir do |tmpdir|
      bundle_dir, ruby_install_dir, ruby_build_path = setup_extension_dirs(tmpdir)
      gem_ext_dir = File.join(bundle_dir, "gems", "nokogiri-1.0", "ext", "nokogiri")
      FileUtils.mkdir_p(gem_ext_dir)
      File.write(File.join(gem_ext_dir, "extconf.rb"), "require 'mkmf'\ncreate_makefile('nokogiri')")

      mock_extension_tasks(ruby_install_dir, ruby_build_path, bundle_dir)

      extensions = Kompo::FindNativeExtensions.extensions

      assert_equal 1, extensions.size
      assert_equal "nokogiri", extensions.first[:gem_ext_name]
      refute extensions.first[:is_rust]
    end
  end

  def test_find_native_extensions_detects_rust_extensions
    Dir.mktmpdir do |tmpdir|
      bundle_dir, ruby_install_dir, ruby_build_path = setup_extension_dirs(tmpdir)
      gem_ext_dir = File.join(bundle_dir, "gems", "rb_sys_test-1.0", "ext", "rb_sys_test")
      FileUtils.mkdir_p(gem_ext_dir)
      File.write(File.join(gem_ext_dir, "extconf.rb"), "require 'mkmf'")
      File.write(File.join(gem_ext_dir, "Cargo.toml"), "[package]\nname = \"rb_sys_test\"")

      mock_extension_tasks(ruby_install_dir, ruby_build_path, bundle_dir)

      extensions = Kompo::FindNativeExtensions.extensions

      assert_equal 1, extensions.size
      assert extensions.first[:is_rust]
      assert extensions.first[:cargo_toml]
    end
  end

  private

  def setup_extension_dirs(tmpdir)
    bundle_dir = File.join(tmpdir, "bundle", "ruby", "3.4.0")
    ruby_install_dir = File.join(tmpdir, "ruby_install")
    ruby_build_path = File.join(tmpdir, "ruby_build")
    lib_dir = File.join(ruby_install_dir, "lib")
    FileUtils.mkdir_p([bundle_dir, lib_dir, ruby_build_path])
    File.write(File.join(lib_dir, "libruby-static.a"), "")
    [bundle_dir, ruby_install_dir, ruby_build_path]
  end

  def mock_extension_tasks(ruby_install_dir, ruby_build_path, bundle_dir)
    mock_task(Kompo::CopyGemfile, gemfile_exists: true)
    mock_task(Kompo::InstallRuby,
      ruby_version: "3.4.1",
      ruby_build_path: ruby_build_path,
      ruby_install_dir: ruby_install_dir)
    mock_task(Kompo::BundleInstall, bundle_ruby_dir: bundle_dir)
  end
end

class BuildNativeGemTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_build_native_gem_returns_empty_when_no_extensions
    mock_task(Kompo::FindNativeExtensions, extensions: [])
    mock_no_gemfile_setup
    mock_task(Kompo::BundleInstall,
      bundle_ruby_dir: "/path/to/bundle",
      bundler_config_path: "/tmp/.bundle/config")

    exts = Kompo::BuildNativeGem.exts
    exts_dir = Kompo::BuildNativeGem.exts_dir

    assert_equal [], exts
    assert_nil exts_dir
    assert_task_accessed(Kompo::FindNativeExtensions, :extensions)
  end

  def test_build_native_gem_exports_exts_and_exts_dir
    exported = Kompo::BuildNativeGem.exported_methods
    assert_includes exported, :exts
    assert_includes exported, :exts_dir
  end

  def test_parse_cargo_toml_target_name_prefers_lib_name
    content = <<~TOML
      [package]
      name = "package_name"
      version = "0.1.0"

      [lib]
      name = "lib_name"
      crate-type = ["staticlib"]
    TOML

    task = Kompo::BuildNativeGem.allocate
    result = task.send(:parse_cargo_toml_target_name, content)

    assert_equal "lib_name", result
  end

  def test_parse_cargo_toml_target_name_falls_back_to_package_name
    content = <<~TOML
      [package]
      name = "package_name"
      version = "0.1.0"
    TOML

    task = Kompo::BuildNativeGem.allocate
    result = task.send(:parse_cargo_toml_target_name, content)

    assert_equal "package_name", result
  end

  def test_parse_cargo_toml_target_name_returns_nil_when_no_name
    content = <<~TOML
      [dependencies]
      some_crate = "1.0"
    TOML

    task = Kompo::BuildNativeGem.allocate
    result = task.send(:parse_cargo_toml_target_name, content)

    assert_nil result
  end
end
