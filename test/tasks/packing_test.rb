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
      ruby_install_dir = tmpdir / "ruby-install"
      # Create required directories and files
      tmpdir << "ruby-build/ruby-3.4.1/" \
             << "ruby-install/lib/pkgconfig/" \
             << "output/" \
             << "kompo-lib/" \
             << ["main.c", "int main() { return 0; }"] \
             << ["fs.c", "// fs"]

      # Mock CollectDependencies
      deps = Kompo::CollectDependencies::Dependencies.new(
        ruby_install_dir: ruby_install_dir,
        ruby_version: "3.4.1",
        ruby_major_minor: "3.4",
        ruby_build_path: tmpdir / "ruby-build",
        ruby_lib: File.join(ruby_install_dir, "lib"),
        kompo_lib: tmpdir / "kompo-lib",
        main_c: tmpdir / "main.c",
        fs_c: tmpdir / "fs.c",
        exts_dir: tmpdir / "exts",
        deps_lib_paths: "-L/opt/homebrew/opt/gmp/lib",
        static_libs: ["/opt/homebrew/opt/gmp/lib/libgmp.a"]
      )

      mock_task(Kompo::CollectDependencies,
        work_dir: work_dir,
        deps: deps,
        ext_paths: [],
        enc_files: [],
        output_path: tmpdir / "output" / "myapp")

      # Mock pkg-config calls
      @mock.stub(["pkg-config", "--cflags", "#{ruby_install_dir}/lib/pkgconfig/ruby.pc"],
        output: "-I#{ruby_install_dir}/include")
      @mock.stub(["pkg-config", "--variable=MAINLIBS", "#{ruby_install_dir}/lib/pkgconfig/ruby.pc"],
        output: "-lpthread -lm")

      capture_io { Kompo::Packing.run(args: {dry_run: true}) }

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
      ruby_install_dir = tmpdir / "ruby-install"
      # Create required directories and files
      tmpdir << "ruby-build/ruby-3.4.1/" \
             << "ruby-install/lib/pkgconfig/" \
             << "output/" \
             << "kompo-lib/" \
             << ["main.c", "int main() { return 0; }"] \
             << ["fs.c", "// fs"]

      # Mock CollectDependencies
      deps = Kompo::CollectDependencies::Dependencies.new(
        ruby_install_dir: ruby_install_dir,
        ruby_version: "3.4.1",
        ruby_major_minor: "3.4",
        ruby_build_path: tmpdir / "ruby-build",
        ruby_lib: File.join(ruby_install_dir, "lib"),
        kompo_lib: tmpdir / "kompo-lib",
        main_c: tmpdir / "main.c",
        fs_c: tmpdir / "fs.c",
        exts_dir: tmpdir / "exts",
        deps_lib_paths: "-L/usr/lib/x86_64-linux-gnu",
        static_libs: ["/usr/lib/x86_64-linux-gnu/libz.a", "/usr/lib/x86_64-linux-gnu/libgmp.a"]
      )

      mock_task(Kompo::CollectDependencies,
        work_dir: work_dir,
        deps: deps,
        ext_paths: [],
        enc_files: [],
        output_path: tmpdir / "output" / "myapp")

      # Mock pkg-config calls
      @mock.stub(["pkg-config", "--cflags", "#{ruby_install_dir}/lib/pkgconfig/ruby.pc"],
        output: "-I#{ruby_install_dir}/include")
      @mock.stub(["pkg-config", "--variable=MAINLIBS", "#{ruby_install_dir}/lib/pkgconfig/ruby.pc"],
        output: "-lz -lgmp -lpthread -ldl -lm")

      stdout, = capture_io { Kompo::Packing.run(args: {dry_run: true}) }

      # Verify gcc was NOT actually called (dry_run skips execution)
      refute @mock.called?(:run, "gcc"), "gcc should not be executed in dry_run mode"

      # Verify static libraries are linked by full path instead of -l flags
      assert_includes stdout, "/usr/lib/x86_64-linux-gnu/libz.a",
        "dry_run output should contain full path for libz.a"
      assert_includes stdout, "/usr/lib/x86_64-linux-gnu/libgmp.a",
        "dry_run output should contain full path for libgmp.a"

      # Verify -Wl,-Bstatic and -Wl,-Bdynamic are NOT used
      refute_includes stdout, "-Wl,-Bstatic", "should not use -Wl,-Bstatic"
      refute_includes stdout, "-Wl,-Bdynamic", "should not use -Wl,-Bdynamic"
    end
  end
end
