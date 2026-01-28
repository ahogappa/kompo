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

class PackingCommonHelpersTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  # Use ForMacOS as a concrete class that includes CommonHelpers
  class TestHelper
    include Kompo::Packing::CommonHelpers

    public :get_ruby_cflags, :get_ruby_mainlibs, :get_ldflags, :get_libpath, :get_extlibs, :get_gem_libs
  end

  def setup
    @mock = setup_mock_command_runner
    @helper = TestHelper.new
  end

  def teardown
    teardown_mock_command_runner
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
end
