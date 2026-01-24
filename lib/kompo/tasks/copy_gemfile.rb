# frozen_string_literal: true

require 'fileutils'

module Kompo
  # Copy Gemfile, Gemfile.lock, and gemspec files to working directory if they exist
  class CopyGemfile < Taski::Task
    exports :gemfile_exists, :gemspec_paths

    def run
      work_dir = WorkDir.path
      project_dir = Taski.args.fetch(:project_dir, Taski.env.working_directory) || Taski.env.working_directory

      gemfile_path = File.join(project_dir, 'Gemfile')
      gemfile_lock_path = File.join(project_dir, 'Gemfile.lock')

      @gemfile_exists = File.exist?(gemfile_path)
      @gemspec_paths = []

      if @gemfile_exists
        FileUtils.cp(gemfile_path, work_dir)
        puts 'Copied: Gemfile'

        if File.exist?(gemfile_lock_path)
          FileUtils.cp(gemfile_lock_path, work_dir)
          puts 'Copied: Gemfile.lock'
        end

        # Copy gemspec files if Gemfile references gemspec
        copy_gemspec_if_needed(gemfile_path, project_dir, work_dir)
      else
        puts 'No Gemfile found, skipping'
      end
    end

    def clean
      return unless @gemfile_exists

      work_dir = WorkDir.path
      return unless work_dir && Dir.exist?(work_dir)

      gemfile = File.join(work_dir, 'Gemfile')
      gemfile_lock = File.join(work_dir, 'Gemfile.lock')

      FileUtils.rm_f(gemfile)
      FileUtils.rm_f(gemfile_lock)

      # Clean up copied gemspec files
      (@gemspec_paths || []).each do |gemspec|
        FileUtils.rm_f(gemspec)
      end

      puts 'Cleaned up Gemfile'
    end

    private

    def copy_gemspec_if_needed(gemfile_path, project_dir, work_dir)
      gemfile_content = File.read(gemfile_path)

      # Check if Gemfile contains a gemspec directive
      return unless gemfile_content.match?(/^\s*gemspec\b/)

      # Copy all .gemspec files from project directory
      gemspec_files = Dir.glob(File.join(project_dir, '*.gemspec'))
      gemspec_files.each do |gemspec_path|
        dest_path = File.join(work_dir, File.basename(gemspec_path))
        FileUtils.cp(gemspec_path, dest_path)
        @gemspec_paths << dest_path
        puts "Copied: #{File.basename(gemspec_path)}"
      end

      if gemspec_files.empty?
        warn 'Warning: Gemfile contains gemspec directive but no .gemspec files found'
      end
    end
  end
end
