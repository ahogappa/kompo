# frozen_string_literal: true

require_relative "../test_helper"

class PackingStructureTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_packing_is_section
    assert Kompo::Packing < Taski::Section
  end

  def test_packing_has_output_path_interface
    assert_includes Kompo::Packing.exported_methods, :output_path
  end
end

class PackingCommonHelpersTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  # Use a test helper class that includes CommonHelpers
  class TestHelper
    include Kompo::Packing::CommonHelpers

    public :get_ruby_cflags, :get_ruby_mainlibs, :get_ldflags, :get_libpath, :get_extlibs, :get_gem_libs
  end

  def setup
    super
    @mock = setup_mock_command_runner
    @helper = TestHelper.new
  end

  def teardown
    teardown_mock_command_runner
    super
  end

  def test_get_ruby_cflags
    @mock.stub(["pkg-config", "--cflags", "/install/lib/pkgconfig/ruby.pc"],
      output: "-I/install/include/ruby-3.4 -DRUBY_EXPORT", success: true)

    cflags = @helper.get_ruby_cflags("/install")

    assert_includes cflags, "-I/install/include/ruby-3.4"
    assert_includes cflags, "-DRUBY_EXPORT"
  end

  def test_get_ruby_mainlibs
    @mock.stub(["pkg-config", "--variable=MAINLIBS", "/install/lib/pkgconfig/ruby.pc"],
      output: "-lpthread -lm -lz", success: true)

    mainlibs = @helper.get_ruby_mainlibs("/install")

    assert_equal "-lpthread -lm -lz", mainlibs
  end

  def test_get_ldflags
    Dir.mktmpdir do |tmpdir|
      work_dir = tmpdir
      gem_ext_dir = File.join(work_dir, "bundle", "ruby", "3.4.0", "gems", "testgem-1.0", "ext", "testgem")
      FileUtils.mkdir_p(gem_ext_dir)
      File.write(File.join(gem_ext_dir, "Makefile"), <<~MAKEFILE)
        ldflags  = -L/opt/local/lib
        LDFLAGS  = -L/usr/local/lib -ltest
      MAKEFILE

      ldflags = @helper.get_ldflags(work_dir, "3.4")

      assert_includes ldflags, "-L/opt/local/lib"
      assert_includes ldflags, "-L/usr/local/lib"
      refute_includes ldflags, "-ltest"
    end
  end

  def test_get_libpath
    Dir.mktmpdir do |tmpdir|
      work_dir = tmpdir
      gem_ext_dir = File.join(work_dir, "bundle", "ruby", "3.4.0", "gems", "testgem-1.0", "ext", "testgem")
      FileUtils.mkdir_p(gem_ext_dir)
      File.write(File.join(gem_ext_dir, "Makefile"), <<~MAKEFILE)
        LIBPATH = -L/usr/local/lib -Wl,-rpath,/something
      MAKEFILE

      libpath = @helper.get_libpath(work_dir, "3.4")

      assert_includes libpath, "-L/usr/local/lib"
      refute libpath.any? { |p| p.include?("-Wl,-rpath") }
    end
  end

  def test_get_extlibs
    Dir.mktmpdir do |tmpdir|
      ruby_build_dir = File.join(tmpdir, "ruby-3.4.1")
      ext_dir = File.join(ruby_build_dir, "ext", "openssl")
      FileUtils.mkdir_p(ext_dir)
      File.write(File.join(ext_dir, "Makefile"), <<~MAKEFILE)
        LIBS = -lssl -lcrypto
      MAKEFILE

      libs = @helper.get_extlibs(tmpdir, "3.4.1")

      assert_includes libs, "-lssl"
      assert_includes libs, "-lcrypto"
    end
  end

  def test_get_extlibs_with_libs_assignment
    Dir.mktmpdir do |tmpdir|
      ruby_build_dir = File.join(tmpdir, "ruby-3.4.1")
      ext_dir = File.join(ruby_build_dir, "ext", "zlib")
      FileUtils.mkdir_p(ext_dir)
      File.write(File.join(ext_dir, "Makefile"), <<~MAKEFILE)
        LIBS += -lz
      MAKEFILE

      libs = @helper.get_extlibs(tmpdir, "3.4.1")

      assert_includes libs, "-lz"
    end
  end

  def test_get_gem_libs
    Dir.mktmpdir do |tmpdir|
      work_dir = tmpdir
      gem_ext_dir = File.join(work_dir, "bundle", "ruby", "3.4.0", "gems", "testgem-1.0", "ext", "testgem")
      FileUtils.mkdir_p(gem_ext_dir)
      File.write(File.join(gem_ext_dir, "Makefile"), <<~MAKEFILE)
        LIBS = -ltest -lhelper
      MAKEFILE

      libs = @helper.get_gem_libs(work_dir, "3.4")

      assert_includes libs, "-ltest"
      assert_includes libs, "-lhelper"
    end
  end

  def test_get_gem_libs_with_static_lib_path
    Dir.mktmpdir do |tmpdir|
      work_dir = tmpdir
      gem_ext_dir = File.join(work_dir, "bundle", "ruby", "3.4.0", "gems", "testgem-1.0", "ext", "testgem")
      FileUtils.mkdir_p(gem_ext_dir)
      # Some Makefiles have full paths to static libraries
      File.write(File.join(gem_ext_dir, "Makefile"), <<~MAKEFILE)
        LIBS = /usr/local/lib/libfoo.a -lbar
      MAKEFILE

      libs = @helper.get_gem_libs(work_dir, "3.4")

      # Static lib path should be converted to -l flag
      assert_includes libs, "-lfoo"
      assert_includes libs, "-lbar"
    end
  end
end
