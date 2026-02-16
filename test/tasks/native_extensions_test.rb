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
end

class BuildNativeGemWithMockTest < Minitest::Test
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

  def test_build_prebuilt_extension_does_not_run_extconf
    Dir.mktmpdir do |tmpdir|
      work_dir = File.join(tmpdir, "work")
      FileUtils.mkdir_p(work_dir)

      ext_dir = File.join(tmpdir, "ext", "bigdecimal")
      FileUtils.mkdir_p(ext_dir)
      File.write(File.join(ext_dir, "Makefile"), <<~MAKEFILE)
        TARGET = bigdecimal
        DLLIB = $(TARGET).bundle
        target_prefix = /bigdecimal
      MAKEFILE

      mock_task(Kompo::WorkDir, path: work_dir)
      mock_task(Kompo::InstallRuby, ruby_version: "3.4.1")
      mock_task(Kompo::FindNativeExtensions, extensions: [
        {
          dir_name: ext_dir,
          gem_ext_name: "bigdecimal",
          is_rust: false,
          is_prebuilt: true
        }
      ])
      mock_args(no_cache: true)

      capture_io { Kompo::BuildNativeGem.run }

      # Verify no extconf.rb or make commands were called for prebuilt extensions
      refute @mock.called?(:capture_all, "ruby", "extconf.rb")
      refute @mock.called?(:capture_all, "make")
    end
  end

  def test_build_c_extension_runs_extconf_and_make
    Dir.mktmpdir do |tmpdir|
      work_dir = File.join(tmpdir, "work")
      FileUtils.mkdir_p(work_dir)

      ext_dir = File.join(tmpdir, "ext", "testgem")
      FileUtils.mkdir_p(ext_dir)
      File.write(File.join(ext_dir, "extconf.rb"), "require 'mkmf'")

      # Stub extconf.rb execution - it creates Makefile
      @mock.stub(["ruby", "extconf.rb"], output: "", success: true)

      # Create Makefile after extconf.rb "runs"
      makefile_content = <<~MAKEFILE
        TARGET = testgem
        DLLIB = $(TARGET).bundle
        target_prefix =
        OBJS = testgem.o helper.o
      MAKEFILE

      # Stub make execution
      @mock.stub(["make", "-C", ext_dir, "testgem.o", "helper.o", "--always-make"],
        output: "Compiling...", success: true)

      mock_task(Kompo::WorkDir, path: work_dir)
      mock_task(Kompo::InstallRuby, ruby_version: "3.4.1")
      mock_task(Kompo::FindNativeExtensions, extensions: [
        {
          dir_name: ext_dir,
          gem_ext_name: "testgem",
          is_rust: false,
          is_prebuilt: false
        }
      ])
      mock_args(no_cache: true)

      # Create Makefile and .o files to simulate build
      File.write(File.join(ext_dir, "Makefile"), makefile_content)
      File.write(File.join(ext_dir, "testgem.o"), "fake object")
      File.write(File.join(ext_dir, "helper.o"), "fake object")

      capture_io { Kompo::BuildNativeGem.run }

      assert @mock.called?(:capture_all, "ruby", "extconf.rb")
      assert @mock.called?(:capture_all, "make", "-C", ext_dir)
    end
  end

  def test_build_rust_extension_runs_cargo
    Dir.mktmpdir do |tmpdir|
      work_dir = File.join(tmpdir, "work")
      FileUtils.mkdir_p(work_dir)

      ext_dir = File.join(tmpdir, "ext", "rustgem")
      FileUtils.mkdir_p(ext_dir)
      cargo_toml = File.join(ext_dir, "Cargo.toml")
      File.write(cargo_toml, <<~TOML)
        [package]
        name = "rustgem"
        version = "0.1.0"

        [lib]
        name = "rustgem"
        crate-type = ["staticlib"]
      TOML

      # Create target directory and .a file
      target_dir = File.join(ext_dir, "target", "release")
      FileUtils.mkdir_p(target_dir)
      File.write(File.join(target_dir, "librustgem.a"), "fake static lib")

      mock_task(Kompo::CargoPath, path: "/usr/local/bin/cargo")
      mock_task(Kompo::WorkDir, path: work_dir)
      mock_task(Kompo::InstallRuby, ruby_version: "3.4.1")
      mock_task(Kompo::FindNativeExtensions, extensions: [
        {
          dir_name: ext_dir,
          gem_ext_name: "rustgem",
          is_rust: true,
          is_prebuilt: false,
          cargo_toml: cargo_toml
        }
      ])
      mock_args(no_cache: true)

      capture_io { Kompo::BuildNativeGem.run }

      assert @mock.called?(:run, "/usr/local/bin/cargo", "rustc", "--release")
    end
  end
end
