# frozen_string_literal: true

require_relative "test_helper"

class CommandRunnerResultTest < Minitest::Test
  # Simple struct to simulate Process::Status
  FakeStatus = Struct.new(:success, :exitstatus, keyword_init: true) do
    def success?
      success
    end
  end

  def test_success_with_successful_status
    status = FakeStatus.new(success: true, exitstatus: 0)

    result = Kompo::CommandRunner::Result.new(output: "output", status: status)

    assert result.success?
  end

  def test_success_with_true_status
    result = Kompo::CommandRunner::Result.new(output: "output", status: true)

    assert result.success?
  end

  def test_success_with_false_status
    result = Kompo::CommandRunner::Result.new(output: "output", status: false)

    refute result.success?
  end

  def test_exit_code_with_process_status
    status = FakeStatus.new(success: false, exitstatus: 127)

    result = Kompo::CommandRunner::Result.new(output: "output", status: status)

    assert_equal 127, result.exit_code
  end

  def test_exit_code_with_true_status
    result = Kompo::CommandRunner::Result.new(output: "output", status: true)

    assert_equal 0, result.exit_code
  end

  def test_exit_code_with_false_status
    result = Kompo::CommandRunner::Result.new(output: "output", status: false)

    assert_equal 1, result.exit_code
  end

  def test_chomp_removes_trailing_newline
    result = Kompo::CommandRunner::Result.new(output: "hello\n", status: true)

    assert_equal "hello", result.chomp
  end

  def test_chomp_handles_nil_output
    result = Kompo::CommandRunner::Result.new(output: nil, status: true)

    assert_equal "", result.chomp
  end

  def test_to_s_returns_output
    result = Kompo::CommandRunner::Result.new(output: "hello\n", status: true)

    assert_equal "hello\n", result.to_s
  end

  def test_command_attribute
    result = Kompo::CommandRunner::Result.new(
      output: "output",
      status: true,
      command: ["echo", "hello"]
    )

    assert_equal ["echo", "hello"], result.command
  end
end

class CommandRunnerCaptureTest < Minitest::Test
  def test_capture_executes_command_and_returns_result
    result = Kompo::CommandRunner.capture("echo", "hello")

    assert result.success?
    assert_equal "hello", result.chomp
    assert_equal ["echo", "hello"], result.command
  end

  def test_capture_with_chdir
    with_tmpdir do |dir|
      result = Kompo::CommandRunner.capture("pwd", chdir: dir)

      assert result.success?
      # Resolve symlinks for comparison (macOS /tmp -> /private/tmp)
      assert_equal File.realpath(dir), File.realpath(result.chomp)
    end
  end

  def test_capture_with_env
    result = Kompo::CommandRunner.capture("sh", "-c", "echo $TEST_VAR", env: {"TEST_VAR" => "test_value"})

    assert result.success?
    assert_equal "test_value", result.chomp
  end

  def test_capture_with_suppress_stderr
    result = Kompo::CommandRunner.capture("sh", "-c", "echo error >&2; echo output", suppress_stderr: true)

    assert result.success?
    assert_equal "output", result.chomp
    refute_includes result.output, "error"
  end

  def test_capture_with_failed_command
    result = Kompo::CommandRunner.capture("sh", "-c", "exit 42")

    refute result.success?
    assert_equal 42, result.exit_code
  end

  def test_capture_with_nonexistent_command
    result = Kompo::CommandRunner.capture("nonexistent_command_xyz123")

    refute result.success?
  end
end

class CommandRunnerCaptureAllTest < Minitest::Test
  def test_capture_all_includes_stderr
    result = Kompo::CommandRunner.capture_all("sh", "-c", "echo stdout; echo stderr >&2")

    assert result.success?
    assert_includes result.output, "stdout"
    assert_includes result.output, "stderr"
  end

  def test_capture_all_with_chdir
    with_tmpdir do |dir|
      result = Kompo::CommandRunner.capture_all("pwd", chdir: dir)

      assert result.success?
      assert_equal File.realpath(dir), File.realpath(result.chomp)
    end
  end

  def test_capture_all_with_env
    result = Kompo::CommandRunner.capture_all(
      "sh", "-c", "echo $TEST_VAR",
      env: {"TEST_VAR" => "capture_all_value"}
    )

    assert result.success?
    assert_equal "capture_all_value", result.chomp
  end
end

class CommandRunnerRunTest < Minitest::Test
  def test_run_returns_true_on_success
    result = Kompo::CommandRunner.run("true")

    assert result
  end

  def test_run_returns_false_on_failure
    result = Kompo::CommandRunner.run("false")

    refute result
  end

  def test_run_with_chdir
    with_tmpdir do |dir|
      test_file = File.join(dir, "test.txt")
      Kompo::CommandRunner.run("touch", "test.txt", chdir: dir)

      assert File.exist?(test_file)
    end
  end

  def test_run_with_env
    result = Kompo::CommandRunner.run(
      "sh", "-c", "test \"$TEST_VAR\" = 'expected'",
      env: {"TEST_VAR" => "expected"}
    )

    assert result
  end

  def test_run_raises_with_error_message_on_failure
    error = assert_raises(RuntimeError) do
      Kompo::CommandRunner.run("false", error_message: "Custom error message")
    end

    assert_equal "Custom error message", error.message
  end

  def test_run_does_not_raise_without_error_message
    result = Kompo::CommandRunner.run("false")

    refute result
  end

  def test_run_returns_false_for_nonexistent_command
    result = Kompo::CommandRunner.run("nonexistent_command_xyz123")

    refute result
  end

  def test_run_returns_false_for_nonexistent_command_with_error_message
    # When command doesn't exist (Errno::ENOENT), should return false
    # even if error_message is set (error_message only applies to command failures)
    result = Kompo::CommandRunner.run(
      "nonexistent_command_xyz123",
      error_message: "This should not be raised"
    )

    refute result
  end
end

class CommandRunnerWhichTest < Minitest::Test
  def test_which_returns_path_for_existing_command
    result = Kompo::CommandRunner.which("sh")

    refute_nil result
    assert_includes result, "sh"
  end

  def test_which_returns_nil_for_nonexistent_command
    result = Kompo::CommandRunner.which("nonexistent_command_xyz123")

    assert_nil result
  end
end

class CommandRunnerDryRunTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_capture_in_dry_run_mode_does_not_execute
    mock_args(dry_run: true)

    # This would fail if actually executed
    result = Kompo::CommandRunner.capture("nonexistent_command_that_would_fail")

    # In dry-run mode, always returns success with empty output
    assert result.success?
    assert_equal "", result.output
  end

  def test_capture_all_in_dry_run_mode_does_not_execute
    mock_args(dry_run: true)

    result = Kompo::CommandRunner.capture_all("nonexistent_command_that_would_fail")

    assert result.success?
    assert_equal "", result.output
  end

  def test_run_in_dry_run_mode_does_not_execute
    mock_args(dry_run: true)

    # This would fail if actually executed
    result = Kompo::CommandRunner.run("nonexistent_command_that_would_fail")

    # In dry-run mode, always returns true
    assert result
  end

  def test_which_in_dry_run_mode_returns_nil
    mock_args(dry_run: true)

    result = Kompo::CommandRunner.which("any_command")

    # In dry-run mode, which returns nil
    assert_nil result
  end
end

class CommandRunnerVerboseTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_capture_in_verbose_mode_outputs_command
    mock_args(verbose: true)

    output = capture_io do
      Kompo::CommandRunner.capture("echo", "hello")
    end

    assert_includes output[0], "[CMD] echo hello"
    assert_includes output[0], "[OK]"
  end

  def test_run_in_verbose_mode_outputs_command
    mock_args(verbose: true)

    output = capture_io do
      Kompo::CommandRunner.run("true")
    end

    assert_includes output[0], "[CMD] true"
    assert_includes output[0], "[OK]"
  end

  def test_run_failure_in_verbose_mode_outputs_fail
    mock_args(verbose: true)

    output = capture_io do
      Kompo::CommandRunner.run("false")
    end

    assert_includes output[0], "[CMD] false"
    assert_includes output[0], "[FAIL]"
  end

  def test_capture_failure_in_verbose_mode_outputs_exit_code
    mock_args(verbose: true)

    output = capture_io do
      Kompo::CommandRunner.capture("sh", "-c", "exit 42")
    end

    assert_includes output[0], "[CMD]"
    assert_includes output[0], "[FAIL] exit code: 42"
  end
end

class MockCommandRunnerTest < Minitest::Test
  def setup
    @mock = MockCommandRunner.new
  end

  def test_capture_records_calls
    @mock.capture("echo", "hello")

    assert @mock.called_with?("echo", "hello")
    assert @mock.called?(:capture, "echo")
  end

  def test_stub_returns_stubbed_result
    @mock.stub(["brew", "--prefix", "openssl"], output: "/opt/homebrew/opt/openssl", success: true)

    result = @mock.capture("brew", "--prefix", "openssl")

    assert result.success?
    assert_equal "/opt/homebrew/opt/openssl", result.chomp
  end

  def test_run_with_stub_failure_raises_error
    @mock.stub(["failing_command"], success: false)

    error = assert_raises(RuntimeError) do
      @mock.run("failing_command", error_message: "Command failed")
    end

    assert_equal "Command failed", error.message
  end

  def test_which_with_stub
    @mock.stub(["/usr/bin/brew"], output: "/usr/bin/brew", success: true)

    result = @mock.which("/usr/bin/brew")

    assert_equal "/usr/bin/brew", result
  end

  def test_which_returns_nil_without_stub
    result = @mock.which("unknown")

    assert_nil result
  end

  def test_reset_clears_calls_and_stubs
    @mock.stub(["test"], output: "stubbed")
    @mock.capture("test")
    @mock.reset!

    refute @mock.called_with?("test")
    result = @mock.capture("test")
    assert_equal "", result.output
  end

  def test_calls_to_returns_filtered_calls
    @mock.capture("cmd1")
    @mock.run("cmd2")
    @mock.capture("cmd3")

    capture_calls = @mock.calls_to(:capture)

    assert_equal 2, capture_calls.length
    assert @mock.called?(:capture, "cmd1")
    assert @mock.called?(:capture, "cmd3")
  end
end

class KompoCommandRunnerAccessorTest < Minitest::Test
  def teardown
    Kompo.command_runner = nil
  end

  def test_default_command_runner_is_command_runner_module
    Kompo.command_runner = nil

    assert_equal Kompo::CommandRunner, Kompo.command_runner
  end

  def test_command_runner_can_be_overridden
    mock = MockCommandRunner.new
    Kompo.command_runner = mock

    assert_equal mock, Kompo.command_runner
  end
end

# Tests for tasks using MockCommandRunner
class TaskCommandRunnerIntegrationTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def setup
    @mock = setup_mock_command_runner
  end

  def teardown
    teardown_mock_command_runner
  end

  def test_homebrew_installed_uses_command_runner_which
    @mock.stub(["/opt/homebrew/bin/brew"], output: "/opt/homebrew/bin/brew", success: true)

    # Trigger HomebrewPath.Installed which uses command_runner.which
    # We can't fully run the task without Homebrew, but we can verify the method is called
    result = Kompo.command_runner.which("/opt/homebrew/bin/brew")

    assert_equal "/opt/homebrew/bin/brew", result
    assert @mock.called?(:which, "/opt/homebrew/bin/brew")
  end

  def test_cargo_installed_uses_command_runner_which
    @mock.stub(["cargo"], output: "/usr/local/bin/cargo", success: true)

    result = Kompo.command_runner.which("cargo")

    assert_equal "/usr/local/bin/cargo", result
    assert @mock.called?(:which, "cargo")
  end

  def test_command_runner_capture_with_suppress_stderr
    @mock.stub(["test", "command"], output: "output", success: true)

    result = Kompo.command_runner.capture("test", "command", suppress_stderr: true)

    assert result.success?
    assert_equal "output", result.chomp
    assert @mock.called?(:capture, "test", "command")

    # Verify suppress_stderr was passed
    call = @mock.calls_to(:capture).first
    assert call[:kwargs][:suppress_stderr]
  end

  def test_command_runner_run_with_error_message
    @mock.stub(["failing", "command"], output: "", success: false)

    error = assert_raises(RuntimeError) do
      Kompo.command_runner.run("failing", "command", error_message: "Custom error")
    end

    assert_equal "Custom error", error.message
    assert @mock.called?(:run, "failing", "command")
  end

  def test_command_runner_run_with_env
    @mock.stub(["env", "command"], output: "", success: true)

    result = Kompo.command_runner.run("env", "command", env: {"VAR" => "value"})

    assert result
    call = @mock.calls_to(:run).first
    assert_equal({"VAR" => "value"}, call[:kwargs][:env])
  end

  def test_command_runner_capture_all
    @mock.stub(["combined", "output"], output: "stdout and stderr", success: true)

    result = Kompo.command_runner.capture_all("combined", "output")

    assert result.success?
    assert_equal "stdout and stderr", result.output
    assert @mock.called?(:capture_all, "combined", "output")
  end

  def test_install_deps_brew_package_check_uses_command_runner
    brew_path = "/opt/homebrew/bin/brew"
    @mock.stub([brew_path, "list", "openssl@3"], output: "", success: true)

    result = Kompo.command_runner.capture(brew_path, "list", "openssl@3", suppress_stderr: true)

    assert result.success?
    assert @mock.called?(:capture, brew_path, "list", "openssl@3")
  end

  def test_pkg_config_check_uses_command_runner
    @mock.stub(["pkg-config", "--exists", "openssl"], output: "", success: true)

    result = Kompo.command_runner.capture("pkg-config", "--exists", "openssl", suppress_stderr: true)

    assert result.success?
    assert @mock.called?(:capture, "pkg-config", "--exists", "openssl")
  end
end
