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
    with_tmpdir do |tmpdir|
      bundle_dir, ruby_install_dir, ruby_build_path = setup_extension_dirs(tmpdir)
      tmpdir << ["bundle/ruby/3.4.0/gems/nokogiri-1.0/ext/nokogiri/extconf.rb", "require 'mkmf'\ncreate_makefile('nokogiri')"]

      mock_extension_tasks(ruby_install_dir, ruby_build_path, bundle_dir)

      extensions = Kompo::FindNativeExtensions.extensions

      assert_equal 1, extensions.size
      assert_equal "nokogiri", extensions.first[:gem_ext_name]
      refute extensions.first[:is_rust]
    end
  end

  def test_find_native_extensions_detects_rust_extensions
    with_tmpdir do |tmpdir|
      bundle_dir, ruby_install_dir, ruby_build_path = setup_extension_dirs(tmpdir)
      tmpdir << ["bundle/ruby/3.4.0/gems/rb_sys_test-1.0/ext/rb_sys_test/extconf.rb", "require 'mkmf'"] \
             << ["bundle/ruby/3.4.0/gems/rb_sys_test-1.0/ext/rb_sys_test/Cargo.toml", "[package]\nname = \"rb_sys_test\""]

      mock_extension_tasks(ruby_install_dir, ruby_build_path, bundle_dir)

      extensions = Kompo::FindNativeExtensions.extensions

      assert_equal 1, extensions.size
      assert extensions.first[:is_rust]
      assert extensions.first[:cargo_toml]
    end
  end

  def test_find_native_extensions_finds_bundled_gems
    with_tmpdir do |tmpdir|
      bundle_dir, ruby_install_dir, ruby_build_path = setup_extension_dirs(tmpdir)
      bundled_ext_prefix = "ruby_build/ruby-3.4.1/.bundle/gems/bigdecimal-4.0.1/ext/bigdecimal"

      tmpdir << ["#{bundled_ext_prefix}/extconf.rb", "require 'mkmf'"] \
             << ["#{bundled_ext_prefix}/bigdecimal.o", ""]

      mock_extension_tasks(ruby_install_dir, ruby_build_path, bundle_dir)

      extensions = Kompo::FindNativeExtensions.extensions

      bundled_ext = extensions.find { |e| e[:gem_ext_name] == "bigdecimal" }
      assert bundled_ext, "Expected to find bigdecimal bundled gem extension"
      assert bundled_ext[:is_prebuilt], "Expected bundled gem to be marked as pre-built"
      refute bundled_ext[:is_rust]
    end
  end

  def test_find_native_extensions_skips_bundled_gems_when_no_stdlib
    with_tmpdir do |tmpdir|
      bundle_dir, ruby_install_dir, ruby_build_path = setup_extension_dirs(tmpdir)
      bundled_ext_prefix = "ruby_build/ruby-3.4.1/.bundle/gems/bigdecimal-4.0.1/ext/bigdecimal"

      tmpdir << ["#{bundled_ext_prefix}/extconf.rb", "require 'mkmf'"] \
             << ["#{bundled_ext_prefix}/bigdecimal.o", ""]

      mock_extension_tasks(ruby_install_dir, ruby_build_path, bundle_dir)
      mock_args(no_stdlib: true)

      extensions = Kompo::FindNativeExtensions.extensions

      bundled_ext = extensions.find { |e| e[:gem_ext_name] == "bigdecimal" }
      assert_nil bundled_ext, "Expected bundled gems to be skipped with --no-stdlib"
    end
  end

  def test_find_native_extensions_skips_bundled_gems_without_o_files
    with_tmpdir do |tmpdir|
      bundle_dir, ruby_install_dir, ruby_build_path = setup_extension_dirs(tmpdir)
      bundled_ext_prefix = "ruby_build/ruby-3.4.1/.bundle/gems/bigdecimal-4.0.1/ext/bigdecimal"

      # Create bundled gem directory without .o files
      tmpdir << ["#{bundled_ext_prefix}/extconf.rb", "require 'mkmf'"]
      # No .o files created

      mock_extension_tasks(ruby_install_dir, ruby_build_path, bundle_dir)

      extensions = Kompo::FindNativeExtensions.extensions

      bundled_ext = extensions.find { |e| e[:gem_ext_name] == "bigdecimal" }
      assert_nil bundled_ext, "Expected bundled gems without .o files to be skipped"
    end
  end

  def test_find_native_extensions_prefers_gemfile_over_prebuilt_bundled
    with_tmpdir do |tmpdir|
      bundle_dir, ruby_install_dir, ruby_build_path = setup_extension_dirs(tmpdir)
      bundled_prefix = "ruby_build/ruby-3.4.1/.bundle/gems/bigdecimal-3.1.0/ext/bigdecimal"
      gemfile_prefix = "bundle/ruby/3.4.0/gems/bigdecimal-4.0.0/ext/bigdecimal"

      # Create prebuilt bundled gem and Gemfile gem with same name but different version
      tmpdir << ["#{bundled_prefix}/extconf.rb", "require 'mkmf'"] \
             << ["#{bundled_prefix}/bigdecimal.o", ""] \
             << ["#{gemfile_prefix}/extconf.rb", "require 'mkmf'"]

      gemfile_ext_dir = File.join(tmpdir, gemfile_prefix)

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
    with_tmpdir do |tmpdir|
      bundle_dir, ruby_install_dir, ruby_build_path = setup_extension_dirs(tmpdir)
      bundled_ext_prefix = "ruby_build/ruby-3.4.1/.bundle/gems/fiddle-1.1.0/ext/fiddle"

      tmpdir << ["#{bundled_ext_prefix}/extconf.rb", "require 'mkmf'"] \
             << ["#{bundled_ext_prefix}/lib/fiddle.o", ""]

      mock_extension_tasks(ruby_install_dir, ruby_build_path, bundle_dir)

      extensions = Kompo::FindNativeExtensions.extensions

      fiddle_ext = extensions.find { |e| e[:gem_ext_name] == "fiddle" }
      assert fiddle_ext, "Expected to find fiddle bundled gem with nested .o files"
      assert fiddle_ext[:is_prebuilt], "Expected bundled gem to be marked as pre-built"
    end
  end

  private

  def setup_extension_dirs(tmpdir)
    tmpdir << "bundle/ruby/3.4.0/" \
           << ["ruby_install/lib/libruby-static.a", ""] \
           << "ruby_build/"
    bundle_dir = File.join(tmpdir, "bundle", "ruby", "3.4.0")
    ruby_install_dir = File.join(tmpdir, "ruby_install")
    ruby_build_path = File.join(tmpdir, "ruby_build")
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

    assert_nil exts
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
    with_tmpdir do |tmpdir|
      tmpdir << "work/"
      work_dir = File.join(tmpdir, "work")
      ext_dir = File.join(tmpdir, "ext", "bigdecimal")

      tmpdir << ["ext/bigdecimal/Makefile", <<~MAKEFILE]
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
    with_tmpdir do |tmpdir|
      tmpdir << "work/" << ["ext/testgem/extconf.rb", "require 'mkmf'"]
      work_dir = File.join(tmpdir, "work")
      ext_dir = File.join(tmpdir, "ext", "testgem")

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
      tmpdir << ["ext/testgem/Makefile", makefile_content] \
             << ["ext/testgem/testgem.o", "fake object"] \
             << ["ext/testgem/helper.o", "fake object"]

      capture_io { Kompo::BuildNativeGem.run }

      assert @mock.called?(:capture_all, "ruby", "extconf.rb")
      assert @mock.called?(:capture_all, "make", "-C", ext_dir)
    end
  end

  def test_build_rust_extension_runs_cargo
    with_tmpdir do |tmpdir|
      cargo_toml_content = <<~TOML
        [package]
        name = "rustgem"
        version = "0.1.0"

        [lib]
        name = "rustgem"
        crate-type = ["staticlib"]
      TOML

      tmpdir << "work/" \
             << ["ext/rustgem/Cargo.toml", cargo_toml_content] \
             << ["ext/rustgem/target/release/librustgem.a", "fake static lib"]

      work_dir = File.join(tmpdir, "work")
      ext_dir = File.join(tmpdir, "ext", "rustgem")
      cargo_toml = File.join(ext_dir, "Cargo.toml")

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
