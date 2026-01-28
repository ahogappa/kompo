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
require "tmpdir"
require "fileutils"
require "json"

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
