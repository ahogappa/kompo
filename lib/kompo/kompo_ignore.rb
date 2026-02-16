# frozen_string_literal: true

require "pathspec"

module Kompo
  # Handler for .kompoignore file
  # Uses pathspec gem for gitignore-compatible pattern matching
  class KompoIgnore
    FILENAME = ".kompoignore"

    DEFAULT_CONTENT = <<~IGNORE
      # Kompo ignore patterns
      # Patterns follow .gitignore syntax

      # Build artifacts and compiled files
      *.so
      *.bundle
      *.o
      *.exe
      *.out

      # Package files
      *.gem
      *.jar

      # Archives
      *.gz
    IGNORE

    # Generate a default .kompoignore file in the given directory
    # @param project_dir [String] Directory to create the file in
    # @return [Boolean] true if file was created, false if it already exists
    def self.generate_default(project_dir)
      ignore_path = File.join(project_dir, FILENAME)
      return false if File.exist?(ignore_path)

      File.write(ignore_path, DEFAULT_CONTENT)
      true
    end

    def initialize(project_dir)
      @project_dir = project_dir
      @pathspec = load_pathspec
    end

    # Check if the given relative path should be ignored
    # @param relative_path [String] Path relative to work_dir
    # @return [Boolean] true if the path should be ignored
    def ignore?(relative_path)
      return false unless @pathspec

      @pathspec.match(relative_path)
    end

    # Check if .kompoignore file exists and is enabled
    # @return [Boolean] true if .kompoignore file exists
    def enabled?
      !@pathspec.nil?
    end

    private

    def load_pathspec
      ignore_file = File.join(@project_dir, FILENAME)
      return nil unless File.exist?(ignore_file)

      PathSpec.from_filename(ignore_file)
    end
  end
end
