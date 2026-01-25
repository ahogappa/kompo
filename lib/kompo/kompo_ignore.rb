# frozen_string_literal: true

require "pathspec"

module Kompo
  # Handler for .kompoignore file
  # Uses pathspec gem for gitignore-compatible pattern matching
  class KompoIgnore
    FILENAME = ".kompoignore"

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
