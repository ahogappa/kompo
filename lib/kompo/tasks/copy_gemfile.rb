# frozen_string_literal: true

require 'fileutils'

module Kompo
  # Copy Gemfile and Gemfile.lock to working directory if they exist
  class CopyGemfile < Taski::Task
    exports :gemfile_exists

    def run
      work_dir = WorkDir.path
      project_dir = Taski.args.fetch(:project_dir, Taski.env.working_directory) || Taski.env.working_directory

      gemfile_path = File.join(project_dir, 'Gemfile')
      gemfile_lock_path = File.join(project_dir, 'Gemfile.lock')

      @gemfile_exists = File.exist?(gemfile_path)

      if @gemfile_exists
        FileUtils.cp(gemfile_path, work_dir)
        puts 'Copied: Gemfile'

        if File.exist?(gemfile_lock_path)
          FileUtils.cp(gemfile_lock_path, work_dir)
          puts 'Copied: Gemfile.lock'
        end
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
      puts 'Cleaned up Gemfile'
    end
  end
end
