# frozen_string_literal: true

require 'fileutils'

module Kompo
  # Copy project files (entrypoint and additional files) to working directory
  class CopyProjectFiles < Taski::Task
    exports :entrypoint_path, :additional_paths

    def run
      work_dir = WorkDir.path
      project_dir = Taski.args.fetch(:project_dir, Taski.env.working_directory) || Taski.env.working_directory
      entrypoint = Taski.args.fetch(:entrypoint, 'main.rb')
      files = Taski.args.fetch(:files, [])

      # Copy entrypoint (preserve relative path structure)
      src_entrypoint = File.expand_path(File.join(project_dir, entrypoint))
      raise "Entrypoint not found: #{src_entrypoint}" unless File.exist?(src_entrypoint)

      # Validate source is inside project_dir
      real_project_dir = File.realpath(project_dir)
      real_src = File.realpath(src_entrypoint)
      unless real_src.start_with?(real_project_dir + File::SEPARATOR) || real_src == real_project_dir
        raise "Entrypoint path escapes project directory: #{entrypoint}"
      end

      @entrypoint_path = File.join(work_dir, entrypoint)
      FileUtils.mkdir_p(File.dirname(@entrypoint_path))
      FileUtils.cp(src_entrypoint, @entrypoint_path)
      puts "Copied entrypoint: #{entrypoint}"

      # Copy additional files/directories
      @additional_paths = []
      files.each do |file|
        src = File.expand_path(File.join(project_dir, file))
        next unless File.exist?(src)

        # Validate source is inside project_dir
        real_src = File.realpath(src)
        unless real_src.start_with?(real_project_dir + File::SEPARATOR) || real_src == real_project_dir
          warn "Skipping path that escapes project directory: #{file}"
          next
        end

        dest = File.join(work_dir, file)

        # Validate destination is inside work_dir
        real_work_dir = File.realpath(work_dir)
        expanded_dest = File.expand_path(dest)
        unless expanded_dest.start_with?(real_work_dir + File::SEPARATOR) || expanded_dest == real_work_dir
          warn "Skipping path that would escape work directory: #{file}"
          next
        end

        if File.directory?(src)
          FileUtils.mkdir_p(dest)
          FileUtils.cp_r(src, File.dirname(dest))
        else
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest)
        end
        @additional_paths << dest
        puts "Copied: #{file}"
      end
    end

    def clean
      work_dir = WorkDir.path
      return unless work_dir && Dir.exist?(work_dir)

      real_work_dir = File.realpath(work_dir)
      files = Taski.args.fetch(:files, [])

      # Clean up copied files (with path validation)
      if @entrypoint_path
        expanded_path = File.expand_path(@entrypoint_path)
        FileUtils.rm_f(@entrypoint_path) if expanded_path.start_with?(real_work_dir + File::SEPARATOR)
      end

      files.each do |file|
        path = File.join(work_dir, file)
        expanded_path = File.expand_path(path)
        # Only delete if path is inside work_dir
        FileUtils.rm_rf(path) if expanded_path.start_with?(real_work_dir + File::SEPARATOR) && File.exist?(path)
      end
      puts 'Cleaned up project files'
    end
  end
end
