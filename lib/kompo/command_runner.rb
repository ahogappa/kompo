# frozen_string_literal: true

require "open3"

module Kompo
  # Command execution abstraction layer
  # Provides unified interface for system, Open3, and backtick operations
  # with verbose logging, dry-run mode, and testability support.
  module CommandRunner
    # Result object for capture operations
    class Result
      attr_reader :output, :status, :command

      def initialize(output:, status:, command: nil)
        @output = output
        @status = status
        @command = command
      end

      def success?
        return true if @status == true
        return false if @status == false
        @status&.success? || false
      end

      def exit_code
        return 0 if @status == true
        return 1 if @status == false
        @status&.exitstatus || 0
      end

      def chomp
        @output.to_s.chomp
      end

      def to_s
        @output.to_s
      end
    end

    class << self
      # Capture stdout (replacement for backticks and Open3.capture2)
      # @param command [Array<String>] Command and arguments
      # @param chdir [String, nil] Working directory
      # @param env [Hash, nil] Environment variables
      # @param suppress_stderr [Boolean] Redirect stderr to /dev/null
      # @return [Result]
      def capture(*command, chdir: nil, env: nil, suppress_stderr: false)
        command = command.flatten.map(&:to_s)
        log_command(command)

        if dry_run?
          log_dry_run(command)
          return Result.new(output: "", status: true, command: command)
        end

        opts = build_options(chdir: chdir)
        opts[:err] = File::NULL if suppress_stderr

        begin
          output, status = if env
            Open3.capture2(env, *command, **opts)
          else
            Open3.capture2(*command, **opts)
          end
          log_result(status)
          Result.new(output: output, status: status, command: command)
        rescue => e
          log_error(e)
          Result.new(output: "", status: false, command: command)
        end
      end

      # Capture stdout and stderr combined (replacement for Open3.capture2e)
      # @param command [Array<String>] Command and arguments
      # @param chdir [String, nil] Working directory
      # @param env [Hash, nil] Environment variables
      # @return [Result]
      def capture_all(*command, chdir: nil, env: nil)
        command = command.flatten.map(&:to_s)
        log_command(command)

        if dry_run?
          log_dry_run(command)
          return Result.new(output: "", status: true, command: command)
        end

        opts = build_options(chdir: chdir)

        begin
          output, status = if env
            Open3.capture2e(env, *command, **opts)
          else
            Open3.capture2e(*command, **opts)
          end
          log_result(status)
          Result.new(output: output, status: status, command: command)
        rescue => e
          log_error(e)
          Result.new(output: "", status: false, command: command)
        end
      end

      # Execute command for side effects (replacement for system)
      # Output is captured to avoid interfering with progress display.
      # @param command [Array<String>] Command and arguments
      # @param chdir [String, nil] Working directory
      # @param env [Hash, nil] Environment variables
      # @param error_message [String, nil] Custom error message for failures
      # @return [Boolean] true if command succeeded
      # @raise [RuntimeError] if error_message is provided and command fails
      def run(*command, chdir: nil, env: nil, error_message: nil)
        command = command.flatten.map(&:to_s)
        log_command(command)

        if dry_run?
          log_dry_run(command)
          return true
        end

        opts = build_options(chdir: chdir)
        output_lines = []

        begin
          Open3.popen2e(env || {}, *command, **opts) do |stdin, stdout_stderr, wait_thr|
            stdin.close
            stdout_stderr.each_line do |line|
              output_lines << line
            end

            success = wait_thr.value.success?
            log_result_bool(success)

            if !success && error_message
              # Print captured output on failure for debugging
              warn output_lines.join unless output_lines.empty?
              raise error_message
            end

            return success
          end
        rescue RuntimeError
          # Re-raise intentional RuntimeError from error_message
          raise
        rescue => e
          log_result_bool(false)
          warn output_lines.join unless output_lines.empty?
          warn "[CommandRunner] #{e.class}: #{e.message}"
          false
        end
      end

      # Check if a command exists in PATH
      # @param command_name [String] Command name to search for
      # @return [String, nil] Full path to command or nil if not found
      def which(command_name)
        log_command(["which", command_name]) if verbose?

        if dry_run?
          log_dry_run(["which", command_name])
          return nil
        end

        result = capture("which", command_name, suppress_stderr: true)
        path = result.chomp
        path.empty? ? nil : path
      end

      private

      def verbose?
        defined?(Taski) && Taski.args&.[](:verbose)
      end

      def dry_run?
        defined?(Taski) && Taski.args&.[](:dry_run)
      end

      def log_command(command)
        return unless verbose?
        puts "[CMD] #{command.join(" ")}"
      end

      def log_dry_run(command)
        puts "[DRY-RUN] Would execute: #{command.join(" ")}"
      end

      def log_result(status)
        return unless verbose?
        if status.success?
          puts "[OK]"
        else
          puts "[FAIL] exit code: #{status.exitstatus}"
        end
      end

      def log_result_bool(success)
        return unless verbose?
        if success
          puts "[OK]"
        else
          puts "[FAIL]"
        end
      end

      def log_error(error)
        return unless verbose?
        puts "[ERROR] #{error.message}"
      end

      def build_options(chdir: nil)
        opts = {}
        opts[:chdir] = chdir if chdir
        opts
      end
    end
  end
end
