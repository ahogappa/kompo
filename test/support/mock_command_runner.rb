# frozen_string_literal: true

# Mock implementation of Kompo::CommandRunner for testing
# Allows recording calls and stubbing responses
class MockCommandRunner
  attr_reader :recorded_calls

  def initialize
    @recorded_calls = []
    @stub_results = {}
  end

  # Stub a specific command to return a given result
  # @param args [Array] Command arguments to match
  # @param output [String] Output to return
  # @param success [Boolean] Whether the command succeeded
  def stub(args, output: "", success: true)
    @stub_results[args] = MockResult.new(output: output, success: success)
  end

  # Capture stdout (matches CommandRunner.capture signature)
  def capture(*command, chdir: nil, env: nil, suppress_stderr: false)
    command = command.flatten.map(&:to_s)
    record(:capture, command, chdir: chdir, env: env, suppress_stderr: suppress_stderr)
    find_stub(command) || default_result
  end

  # Capture stdout+stderr (matches CommandRunner.capture_all signature)
  def capture_all(*command, chdir: nil, env: nil)
    command = command.flatten.map(&:to_s)
    record(:capture_all, command, chdir: chdir, env: env)
    find_stub(command) || default_result
  end

  # Execute command (matches CommandRunner.run signature)
  def run(*command, chdir: nil, env: nil, error_message: nil)
    command = command.flatten.map(&:to_s)
    record(:run, command, chdir: chdir, env: env, error_message: error_message)
    stub = find_stub(command)
    success = stub ? stub.success? : true

    if !success && error_message
      raise error_message
    end

    success
  end

  # Check if command exists (matches CommandRunner.which signature)
  def which(command_name)
    record(:which, [command_name.to_s])
    stub = find_stub([command_name.to_s])
    stub&.chomp
  end

  # Check if a command was called with given arguments
  # @param expected_args [Array] Arguments to check for (subset matching)
  # @return [Boolean]
  def called_with?(*expected_args)
    expected = expected_args.map(&:to_s)
    @recorded_calls.any? { |call| (expected - call[:args]).empty? }
  end

  # Check if a specific method was called with given arguments
  # @param method [Symbol] Method name (:capture, :capture_all, :run, :which)
  # @param expected_args [Array] Arguments to check for (subset matching)
  # @return [Boolean]
  def called?(method, *expected_args)
    expected = expected_args.map(&:to_s)
    @recorded_calls.any? do |call|
      call[:method] == method && (expected - call[:args]).empty?
    end
  end

  # Get all calls to a specific method
  # @param method [Symbol] Method name
  # @return [Array<Hash>]
  def calls_to(method)
    @recorded_calls.select { |call| call[:method] == method }
  end

  # Clear all recorded calls and stubs
  def reset!
    @recorded_calls = []
    @stub_results = {}
  end

  private

  def record(method, args, **kwargs)
    @recorded_calls << {method: method, args: args, kwargs: kwargs}
  end

  def find_stub(args)
    # First try exact match
    return @stub_results[args] if @stub_results.key?(args)

    # Then try partial match (useful for which)
    @stub_results.find { |key, _| (key - args).empty? && (args - key).empty? }&.last
  end

  def default_result
    MockResult.new(output: "", success: true)
  end

  # Simple result object for mock responses
  class MockResult
    attr_reader :output

    def initialize(output:, success:)
      @output = output
      @success = success
    end

    def success?
      @success
    end

    def exit_code
      @success ? 0 : 1
    end

    def chomp
      @output.to_s.chomp
    end

    def to_s
      @output.to_s
    end
  end
end
