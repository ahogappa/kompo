# frozen_string_literal: true

require_relative '../test_helper'

class CheckStdlibsTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_check_stdlibs_accesses_install_ruby
    Dir.mktmpdir do |tmpdir|
      stdlib_root = File.join(tmpdir, 'lib', 'ruby', '3.4.0')
      FileUtils.mkdir_p(stdlib_root)
      mock_install_ruby_with_dir(tmpdir)

      paths = Kompo::CheckStdlibs.paths

      assert_includes paths, stdlib_root
      assert_task_accessed(Kompo::InstallRuby, :ruby_install_dir)
    end
  end

  def test_check_stdlibs_skips_when_no_stdlib_flag_set
    Dir.mktmpdir do |tmpdir|
      stdlib_root = File.join(tmpdir, 'lib', 'ruby', '3.4.0')
      FileUtils.mkdir_p(stdlib_root)
      mock_install_ruby_with_dir(tmpdir)
      mock_args(no_stdlib: true)

      paths = Kompo::CheckStdlibs.paths

      assert_equal [], paths
    end
  end

  def test_check_stdlibs_includes_gem_specifications
    Dir.mktmpdir do |tmpdir|
      stdlib_root = File.join(tmpdir, 'lib', 'ruby', '3.4.0')
      gems_specs = File.join(tmpdir, 'lib', 'ruby', 'gems', '3.4.0', 'specifications')
      FileUtils.mkdir_p([stdlib_root, gems_specs])
      mock_install_ruby_with_dir(tmpdir)

      paths = Kompo::CheckStdlibs.paths

      assert_includes paths, stdlib_root
      assert_includes paths, gems_specs
    end
  end

  private

  def mock_install_ruby_with_dir(dir)
    mock_task(Kompo::InstallRuby,
              ruby_path: '/path/to/ruby',
              ruby_install_dir: dir,
              original_ruby_install_dir: dir,
              ruby_major_minor: '3.4')
  end
end
