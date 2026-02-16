# frozen_string_literal: true

# Coverage measurement must be started before loading any code
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/test/"
    add_filter "/vendor/"
    enable_coverage :branch
    primary_coverage :line
    # Track all Ruby files in lib directory
    track_files "lib/**/*.rb"
  end
end

# Load taski and test helper BEFORE loading kompo tasks
# This ensures TaskExtension is prepended to Taski::Task
# before any task classes are defined
require "taski"
require "taski/test_helper/minitest"

# Disable progress display in tests to prevent TaskOutputRouter from
# intercepting $stderr (which breaks capture_io for warn output)
Taski.progress_display = nil
require "digest"

# Now load kompo (tasks will have TaskExtension prepended)
require_relative "../lib/kompo"
require_relative "support/mock_command_runner"

# Force load all autoloaded constants for accurate coverage measurement
if ENV["COVERAGE"]
  Kompo.constants.each do |const|
    Kompo.const_get(const) if Kompo.autoload?(const)
  rescue LoadError
    # Some constants may not be loadable in test environment
  end
end

require "minitest/autorun"
require "minitest/mock"
require "webmock/minitest"
require "tmpdir"
require "fileutils"
require "json"

# Disable WebMock globally by default so tests that don't need it work normally.
# Tests that use WebMock should call WebMock.enable! in setup.
WebMock.disable!

class TmpDir
  def initialize(path)
    @path = path
  end

  def to_s
    @path
  end

  alias_method :to_str, :to_s

  def <<(entry)
    name, content = parse_entry(entry)

    full_path = File.join(@path, name)
    if name.end_with?("/")
      FileUtils.mkdir_p(full_path)
    else
      FileUtils.mkdir_p(File.dirname(full_path))
      content ? File.write(full_path, content) : FileUtils.touch(full_path)
    end
    self
  end

  private

  def parse_entry(entry)
    case entry
    when String
      [entry, nil]
    when Array
      raise ArgumentError, "expected 1 or 2 elements, got #{entry.size}" if entry.size > 2
      entry
    end
  end
end

class Minitest::Test
  private

  def with_tmpdir
    Dir.mktmpdir do |tmpdir|
      yield TmpDir.new(File.realpath(tmpdir))
    end
  end
end

# Common mock configurations for task tests
module TaskTestHelpers
  STANDARD_RUBY_MOCK = {
    ruby_path: "/path/to/ruby",
    bundler_path: "/path/to/bundler",
    ruby_install_dir: "/path/to/install",
    original_ruby_install_dir: "/path/to/install",
    ruby_version: "3.4.1",
    ruby_major_minor: "3.4",
    ruby_build_path: "/path/to/build"
  }.freeze

  def mock_standard_ruby
    mock_task(Kompo::InstallRuby, **STANDARD_RUBY_MOCK)
  end

  def mock_no_gemfile_setup(work_dir: "/tmp/work", original_dir: "/tmp")
    mock_task(Kompo::CopyGemfile, gemfile_exists: false)
    mock_task(Kompo::WorkDir, path: work_dir, original_dir: original_dir)
    mock_standard_ruby
    mock_task(Kompo::BundleInstall, bundler_config_path: nil, bundle_ruby_dir: nil)
  end

  # Setup MockCommandRunner for testing command executions
  # Returns the mock instance so tests can add stubs
  def setup_mock_command_runner
    @mock_command_runner = MockCommandRunner.new
    Kompo.command_runner = @mock_command_runner
    @mock_command_runner
  end

  # Restore original CommandRunner after test
  def teardown_mock_command_runner
    Kompo.command_runner = nil
  end
end
