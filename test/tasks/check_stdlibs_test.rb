# frozen_string_literal: true

require_relative "../test_helper"

class CheckStdlibsTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_check_stdlibs_accesses_install_ruby
    with_tmpdir do |tmpdir|
      tmpdir << "lib/ruby/3.4.0/"
      mock_install_ruby_with_dir(tmpdir)

      paths = Kompo::CheckStdlibs.paths

      assert_includes paths, File.join(tmpdir, "lib", "ruby", "3.4.0")
      assert_task_accessed(Kompo::InstallRuby, :ruby_install_dir)
    end
  end

  def test_check_stdlibs_skips_when_no_stdlib_flag_set
    with_tmpdir do |tmpdir|
      tmpdir << "lib/ruby/3.4.0/"
      mock_install_ruby_with_dir(tmpdir)
      mock_args(no_stdlib: true)

      paths = Kompo::CheckStdlibs.paths

      assert_equal [], paths
    end
  end

  def test_check_stdlibs_includes_gem_specifications
    with_tmpdir do |tmpdir|
      tmpdir << "lib/ruby/3.4.0/" \
             << "lib/ruby/gems/3.4.0/specifications/"
      mock_install_ruby_with_dir(tmpdir)

      paths = Kompo::CheckStdlibs.paths

      assert_includes paths, File.join(tmpdir, "lib", "ruby", "3.4.0")
      assert_includes paths, File.join(tmpdir, "lib", "ruby", "gems", "3.4.0", "specifications")
    end
  end

  private

  def mock_install_ruby_with_dir(dir)
    mock_task(Kompo::InstallRuby,
      ruby_path: "/path/to/ruby",
      ruby_install_dir: dir,
      original_ruby_install_dir: dir,
      ruby_major_minor: "3.4")
  end
end
