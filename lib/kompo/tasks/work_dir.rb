# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "tmpdir"

module Kompo
  # Create a temporary working directory and change into it
  class WorkDir < Taski::Task
    exports :path, :original_dir

    # Marker file to identify Kompo-created work directories
    MARKER_FILE = ".kompo_work_dir_marker"

    def run
      @original_dir = Dir.pwd

      # Check if Ruby cache exists and use its work_dir path for $LOAD_PATH compatibility
      ruby_version = Taski.args.fetch(:ruby_version, RUBY_VERSION)
      kompo_cache = Taski.args.fetch(:kompo_cache, File.expand_path("~/.kompo/cache"))
      cache_metadata_path = File.join(kompo_cache, ruby_version, "metadata.json")

      if File.exist?(cache_metadata_path)
        begin
          metadata = JSON.parse(File.read(cache_metadata_path))
          cached_work_dir = metadata["work_dir"]

          if cached_work_dir
            # Check if the directory exists and belongs to us (has marker) or doesn't exist at all
            # In CI environments, the temp directory is cleaned between runs, so we recreate it
            if Dir.exist?(cached_work_dir)
              marker_path = File.join(cached_work_dir, MARKER_FILE)
              if File.exist?(marker_path)
                # Directory exists and has our marker - reuse it
                @path = cached_work_dir
                puts "Using cached work directory: #{@path}"
                return
              else
                # Directory exists but wasn't created by Kompo - don't use it
                warn "warn: #{cached_work_dir} exists but is not a Kompo work directory, creating new one"
              end
            else
              # Directory doesn't exist - try to recreate it (common in CI after cache restore)
              # This may fail if the path is from a previous CI run with different permissions
              begin
                FileUtils.mkdir_p(cached_work_dir)
                File.write(File.join(cached_work_dir, MARKER_FILE), "kompo-work-dir")
                @path = cached_work_dir
                puts "Recreated cached work directory: #{@path}"
                return
              rescue Errno::EACCES, Errno::EPERM
                # Permission denied - fall through to create new work_dir
                warn "warn: Cannot recreate #{cached_work_dir} (permission denied), creating new work directory"
              end
            end
          end
        rescue JSON::ParserError
          # Fall through to create new work_dir
        end
      end

      # No valid cache, create new work_dir
      tmpdir = Dir.mktmpdir(SecureRandom.uuid)
      # Resolve symlinks to get the real path
      # On macOS, /var/folders is a symlink to /private/var/folders
      # If we don't resolve this, paths won't match at runtime
      @path = File.realpath(tmpdir)

      # Create marker file to identify this as a Kompo work directory
      File.write(File.join(@path, MARKER_FILE), "kompo-work-dir")

      puts "Working directory: #{@path}"
    end

    def clean
      return unless @path && Dir.exist?(@path)

      # Only remove if marker file exists (confirms this is a Kompo work directory)
      marker_path = File.join(@path, MARKER_FILE)
      unless File.exist?(marker_path)
        puts "Skipping cleanup: #{@path} is not a Kompo work directory"
        return
      end

      FileUtils.rm_rf(@path)
      puts "Cleaned up working directory: #{@path}"
    end
  end
end
