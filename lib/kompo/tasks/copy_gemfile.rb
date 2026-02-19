# frozen_string_literal: true

require "fileutils"

module Kompo
  # Copy Gemfile, Gemfile.lock, and gemspec files to working directory if they exist
  class CopyGemfile < Taski::Task
    exports :gemfile_exists, :gemspec_paths

    def run
      work_dir = WorkDir.path
      project_dir = Taski.args.fetch(:project_dir, Taski.env.working_directory) || Taski.env.working_directory

      # Skip Gemfile processing if --no-gemfile is specified
      if Taski.args[:no_gemfile]
        puts "Skipping Gemfile (--no-gemfile specified)"
        @gemfile_exists = false
        @gemspec_paths = []
        return
      end

      gemfile_path = File.join(project_dir, "Gemfile")
      gemfile_lock_path = File.join(project_dir, "Gemfile.lock")

      begin
        real_project_dir = File.realpath(project_dir)
      rescue Errno::ENOENT
        @gemfile_exists = false
        @gemspec_paths = []
        puts "No Gemfile found, skipping"
        return
      end

      @gemfile_exists = File.exist?(gemfile_path)
      @gemspec_paths = []

      if @gemfile_exists
        unless path_inside_dir?(gemfile_path, real_project_dir)
          warn "warn: Gemfile escapes project directory, skipping"
          @gemfile_exists = false
          return
        end

        FileUtils.cp(gemfile_path, work_dir)
        puts "Copied: Gemfile"

        if File.exist?(gemfile_lock_path)
          if path_inside_dir?(gemfile_lock_path, real_project_dir)
            FileUtils.cp(gemfile_lock_path, work_dir)
            puts "Copied: Gemfile.lock"
          else
            warn "warn: Gemfile.lock escapes project directory, skipping"
          end
        end

        # Copy gemspec files if Gemfile references gemspec
        copy_gemspec_if_needed(gemfile_path, project_dir, work_dir, real_project_dir)
      else
        puts "No Gemfile found, skipping"
      end
    end

    def clean
      return unless @gemfile_exists

      work_dir = WorkDir.path
      return unless work_dir && Dir.exist?(work_dir)

      gemfile = File.join(work_dir, "Gemfile")
      gemfile_lock = File.join(work_dir, "Gemfile.lock")

      FileUtils.rm_f(gemfile)
      FileUtils.rm_f(gemfile_lock)

      # Clean up copied gemspec files
      (@gemspec_paths || []).each do |gemspec|
        FileUtils.rm_f(gemspec)
      end

      puts "Cleaned up Gemfile"
    end

    private

    def path_inside_dir?(path, real_dir)
      return false unless File.exist?(path)

      real_path = File.realpath(path)
      real_path.start_with?(real_dir + File::SEPARATOR) || real_path == real_dir
    rescue Errno::ENOENT, Errno::EACCES
      false
    end

    def copy_gemspec_if_needed(gemfile_path, project_dir, work_dir, real_project_dir)
      gemfile_content = File.read(gemfile_path)

      # Check if Gemfile contains a gemspec directive
      return unless gemfile_content.match?(/^\s*gemspec\b/)

      # Copy all .gemspec files from project directory
      gemspec_files = Dir.glob(File.join(project_dir, "*.gemspec"))
      gemspec_files.each do |gemspec_path|
        unless path_inside_dir?(gemspec_path, real_project_dir)
          warn "warn: #{File.basename(gemspec_path)} escapes project directory, skipping"
          next
        end

        dest_path = File.join(work_dir, File.basename(gemspec_path))
        FileUtils.cp(gemspec_path, dest_path)
        @gemspec_paths << dest_path
        puts "Copied: #{File.basename(gemspec_path)}"
      end

      if gemspec_files.empty?
        warn "warn: Gemfile contains gemspec directive but no .gemspec files found"
      end
    end
  end
end
