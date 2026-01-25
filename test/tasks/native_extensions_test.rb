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

  def test_find_native_extensions_finds_bundled_gems
    Dir.mktmpdir do |tmpdir|
      bundle_dir, ruby_install_dir, ruby_build_path = setup_extension_dirs(tmpdir)

      # Create bundled gem directory structure (Ruby 4.0+)
      bundled_gems_dir = File.join(ruby_build_path, "ruby-3.4.1", ".bundle", "gems")
      bigdecimal_ext_dir = File.join(bundled_gems_dir, "bigdecimal-4.0.1", "ext", "bigdecimal")
      FileUtils.mkdir_p(bigdecimal_ext_dir)
      File.write(File.join(bigdecimal_ext_dir, "extconf.rb"), "require 'mkmf'")
      File.write(File.join(bigdecimal_ext_dir, "bigdecimal.o"), "")

      mock_extension_tasks(ruby_install_dir, ruby_build_path, bundle_dir)

      extensions = Kompo::FindNativeExtensions.extensions

      bundled_ext = extensions.find { |e| e[:gem_ext_name] == "bigdecimal" }
      assert bundled_ext, "Expected to find bigdecimal bundled gem extension"
      assert bundled_ext[:is_prebuilt], "Expected bundled gem to be marked as pre-built"
      refute bundled_ext[:is_rust]
    end
  end

  def test_find_native_extensions_skips_bundled_gems_when_no_stdlib
    Dir.mktmpdir do |tmpdir|
      bundle_dir, ruby_install_dir, ruby_build_path = setup_extension_dirs(tmpdir)

      # Create bundled gem directory structure
      bundled_gems_dir = File.join(ruby_build_path, "ruby-3.4.1", ".bundle", "gems")
      bigdecimal_ext_dir = File.join(bundled_gems_dir, "bigdecimal-4.0.1", "ext", "bigdecimal")
      FileUtils.mkdir_p(bigdecimal_ext_dir)
      File.write(File.join(bigdecimal_ext_dir, "extconf.rb"), "require 'mkmf'")
      File.write(File.join(bigdecimal_ext_dir, "bigdecimal.o"), "")

      mock_extension_tasks(ruby_install_dir, ruby_build_path, bundle_dir)
      mock_args(no_stdlib: true)

      extensions = Kompo::FindNativeExtensions.extensions

      bundled_ext = extensions.find { |e| e[:gem_ext_name] == "bigdecimal" }
      assert_nil bundled_ext, "Expected bundled gems to be skipped with --no-stdlib"
    end
  end

  def test_find_native_extensions_skips_bundled_gems_without_o_files
    Dir.mktmpdir do |tmpdir|
      bundle_dir, ruby_install_dir, ruby_build_path = setup_extension_dirs(tmpdir)

      # Create bundled gem directory without .o files
      bundled_gems_dir = File.join(ruby_build_path, "ruby-3.4.1", ".bundle", "gems")
      bigdecimal_ext_dir = File.join(bundled_gems_dir, "bigdecimal-4.0.1", "ext", "bigdecimal")
      FileUtils.mkdir_p(bigdecimal_ext_dir)
      File.write(File.join(bigdecimal_ext_dir, "extconf.rb"), "require 'mkmf'")
      # No .o files created

      mock_extension_tasks(ruby_install_dir, ruby_build_path, bundle_dir)

      extensions = Kompo::FindNativeExtensions.extensions

      bundled_ext = extensions.find { |e| e[:gem_ext_name] == "bigdecimal" }
      assert_nil bundled_ext, "Expected bundled gems without .o files to be skipped"
    end
  end

  def test_find_native_extensions_prefers_gemfile_over_prebuilt_bundled
    Dir.mktmpdir do |tmpdir|
      bundle_dir, ruby_install_dir, ruby_build_path = setup_extension_dirs(tmpdir)

      # Create prebuilt bundled gem
      bundled_gems_dir = File.join(ruby_build_path, "ruby-3.4.1", ".bundle", "gems")
      bundled_ext_dir = File.join(bundled_gems_dir, "bigdecimal-3.1.0", "ext", "bigdecimal")
      FileUtils.mkdir_p(bundled_ext_dir)
      File.write(File.join(bundled_ext_dir, "extconf.rb"), "require 'mkmf'")
      File.write(File.join(bundled_ext_dir, "bigdecimal.o"), "")

      # Create Gemfile gem with same name but different version
      gemfile_ext_dir = File.join(bundle_dir, "gems", "bigdecimal-4.0.0", "ext", "bigdecimal")
      FileUtils.mkdir_p(gemfile_ext_dir)
      File.write(File.join(gemfile_ext_dir, "extconf.rb"), "require 'mkmf'")

      mock_extension_tasks(ruby_install_dir, ruby_build_path, bundle_dir)

      extensions = Kompo::FindNativeExtensions.extensions

      # Should have exactly one bigdecimal entry
      bigdecimal_exts = extensions.select { |e| e[:gem_ext_name] == "bigdecimal" }
      assert_equal 1, bigdecimal_exts.size, "Expected exactly one bigdecimal extension"

      # Should be the Gemfile version (not prebuilt)
      ext = bigdecimal_exts.first
      refute ext[:is_prebuilt], "Expected Gemfile version to replace prebuilt bundled gem"
      assert_equal gemfile_ext_dir, ext[:dir_name], "Expected dir_name to be from Gemfile version"
    end
  end

  def test_find_native_extensions_finds_bundled_gems_with_nested_o_files
    Dir.mktmpdir do |tmpdir|
      bundle_dir, ruby_install_dir, ruby_build_path = setup_extension_dirs(tmpdir)

      # Create bundled gem with .o files in subdirectory (like lib/)
      bundled_gems_dir = File.join(ruby_build_path, "ruby-3.4.1", ".bundle", "gems")
      fiddle_ext_dir = File.join(bundled_gems_dir, "fiddle-1.1.0", "ext", "fiddle")
      fiddle_lib_dir = File.join(fiddle_ext_dir, "lib")
      FileUtils.mkdir_p(fiddle_lib_dir)
      File.write(File.join(fiddle_ext_dir, "extconf.rb"), "require 'mkmf'")
      # .o files are in lib/ subdirectory
      File.write(File.join(fiddle_lib_dir, "fiddle.o"), "")

      mock_extension_tasks(ruby_install_dir, ruby_build_path, bundle_dir)

      extensions = Kompo::FindNativeExtensions.extensions

      fiddle_ext = extensions.find { |e| e[:gem_ext_name] == "fiddle" }
      assert fiddle_ext, "Expected to find fiddle bundled gem with nested .o files"
      assert fiddle_ext[:is_prebuilt], "Expected bundled gem to be marked as pre-built"
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

  def test_register_prebuilt_extension_parses_makefile
    Dir.mktmpdir do |tmpdir|
      ext_dir = File.join(tmpdir, "bigdecimal")
      FileUtils.mkdir_p(ext_dir)

      makefile_content = <<~MAKEFILE
        TARGET_NAME = bigdecimal
        target_prefix =
        OBJS = bigdecimal.o missing.o
      MAKEFILE
      File.write(File.join(ext_dir, "Makefile"), makefile_content)

      task = Kompo::BuildNativeGem.allocate
      task.instance_variable_set(:@exts, [])
      task.send(:register_prebuilt_extension, ext_dir, "bigdecimal")

      exts = task.instance_variable_get(:@exts)
      assert_equal 1, exts.size
      assert_equal ["bigdecimal", "Init_bigdecimal"], exts.first
    end
  end

  def test_register_prebuilt_extension_with_prefix
    Dir.mktmpdir do |tmpdir|
      ext_dir = File.join(tmpdir, "escape")
      FileUtils.mkdir_p(ext_dir)

      makefile_content = <<~MAKEFILE
        TARGET_NAME = escape
        target_prefix = /cgi
        OBJS = escape.o
      MAKEFILE
      File.write(File.join(ext_dir, "Makefile"), makefile_content)

      task = Kompo::BuildNativeGem.allocate
      task.instance_variable_set(:@exts, [])
      task.send(:register_prebuilt_extension, ext_dir, "escape")

      exts = task.instance_variable_get(:@exts)
      assert_equal 1, exts.size
      assert_equal ["cgi/escape", "Init_escape"], exts.first
    end
  end

  def test_register_prebuilt_extension_raises_without_makefile
    Dir.mktmpdir do |tmpdir|
      ext_dir = File.join(tmpdir, "noext")
      FileUtils.mkdir_p(ext_dir)
      # No Makefile

      task = Kompo::BuildNativeGem.allocate
      task.instance_variable_set(:@exts, [])

      assert_raises(RuntimeError) do
        task.send(:register_prebuilt_extension, ext_dir, "noext")
      end
    end
  end
end
