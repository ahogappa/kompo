# frozen_string_literal: true

require_relative "../test_helper"

class PackingStructureTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_packing_is_task
    assert Kompo::Packing < Taski::Task
  end

  def test_packing_has_output_path_interface
    assert_includes Kompo::Packing.exported_methods, :output_path
  end
end

class PackingForMacOSDryRunTest < Minitest::Test
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

  def test_dry_run_does_not_execute_clang
    skip unless RUBY_PLATFORM.include?("darwin")

    with_tmpdir do |tmpdir|
      work_dir = tmpdir
      ruby_build_dir = File.join(tmpdir, "ruby-build", "ruby-3.4.1")
      ruby_install_dir = File.join(tmpdir, "ruby-install")
      kompo_lib = File.join(tmpdir, "kompo-lib")
      output_path = File.join(tmpdir, "output", "myapp")

      # Create required directories
      FileUtils.mkdir_p(ruby_build_dir)
      FileUtils.mkdir_p(File.join(ruby_install_dir, "lib", "pkgconfig"))
      FileUtils.mkdir_p(File.join(tmpdir, "output"))
      FileUtils.mkdir_p(kompo_lib)

      # Create main.c and fs.c files
      main_c = File.join(tmpdir, "main.c")
      fs_c = File.join(tmpdir, "fs.c")
      File.write(main_c, "int main() { return 0; }")
      File.write(fs_c, "// fs")

      # Mock CollectDependencies
      deps = Kompo::CollectDependencies::Dependencies.new(
        ruby_install_dir: ruby_install_dir,
        ruby_version: "3.4.1",
        ruby_major_minor: "3.4",
        ruby_build_path: File.join(tmpdir, "ruby-build"),
        ruby_lib: File.join(ruby_install_dir, "lib"),
        kompo_lib: kompo_lib,
        main_c: main_c,
        fs_c: fs_c,
        exts_dir: File.join(tmpdir, "exts"),
        deps_lib_paths: "-L/opt/homebrew/opt/gmp/lib",
        static_libs: ["/opt/homebrew/opt/gmp/lib/libgmp.a"]
      )

      mock_task(Kompo::CollectDependencies,
        work_dir: work_dir,
        deps: deps,
        ext_paths: [],
        enc_files: [],
        output_path: output_path)

      mock_args(dry_run: true)

      # Mock pkg-config calls
      @mock.stub(["pkg-config", "--cflags", "#{ruby_install_dir}/lib/pkgconfig/ruby.pc"],
        output: "-I#{ruby_install_dir}/include")
      @mock.stub(["pkg-config", "--variable=MAINLIBS", "#{ruby_install_dir}/lib/pkgconfig/ruby.pc"],
        output: "-lpthread -lm")

      capture_io { Kompo::Packing.run }

      # Verify clang was NOT actually called (dry_run skips execution)
      refute @mock.called?(:run, "clang"), "clang should not be executed in dry_run mode"
    end
  end
end

class PackingForLinuxDryRunTest < Minitest::Test
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

  def test_dry_run_does_not_execute_gcc
    skip if RUBY_PLATFORM.include?("darwin")

    with_tmpdir do |tmpdir|
      work_dir = tmpdir
      ruby_build_dir = File.join(tmpdir, "ruby-build", "ruby-3.4.1")
      ruby_install_dir = File.join(tmpdir, "ruby-install")
      kompo_lib = File.join(tmpdir, "kompo-lib")
      output_path = File.join(tmpdir, "output", "myapp")

      # Create required directories
      FileUtils.mkdir_p(ruby_build_dir)
      FileUtils.mkdir_p(File.join(ruby_install_dir, "lib", "pkgconfig"))
      FileUtils.mkdir_p(File.join(tmpdir, "output"))
      FileUtils.mkdir_p(kompo_lib)

      # Create main.c and fs.c files
      main_c = File.join(tmpdir, "main.c")
      fs_c = File.join(tmpdir, "fs.c")
      File.write(main_c, "int main() { return 0; }")
      File.write(fs_c, "// fs")

      # Mock CollectDependencies
      deps = Kompo::CollectDependencies::Dependencies.new(
        ruby_install_dir: ruby_install_dir,
        ruby_version: "3.4.1",
        ruby_major_minor: "3.4",
        ruby_build_path: File.join(tmpdir, "ruby-build"),
        ruby_lib: File.join(ruby_install_dir, "lib"),
        kompo_lib: kompo_lib,
        main_c: main_c,
        fs_c: fs_c,
        exts_dir: File.join(tmpdir, "exts"),
        deps_lib_paths: "-L/usr/lib/x86_64-linux-gnu",
        static_libs: []
      )

      mock_task(Kompo::CollectDependencies,
        work_dir: work_dir,
        deps: deps,
        ext_paths: [],
        enc_files: [],
        output_path: output_path)

      mock_args(dry_run: true)

      # Mock pkg-config calls
      @mock.stub(["pkg-config", "--cflags", "#{ruby_install_dir}/lib/pkgconfig/ruby.pc"],
        output: "-I#{ruby_install_dir}/include")
      @mock.stub(["pkg-config", "--variable=MAINLIBS", "#{ruby_install_dir}/lib/pkgconfig/ruby.pc"],
        output: "-lpthread -ldl -lm")

      capture_io { Kompo::Packing.run }

      # Verify gcc was NOT actually called (dry_run skips execution)
      refute @mock.called?(:run, "gcc"), "gcc should not be executed in dry_run mode"
    end
  end
end
