# frozen_string_literal: true

require "erb"
require "fileutils"
require "find"

module Kompo
  # Struct to hold file data for embedding
  KompoFile = Struct.new(:path, :bytes)

  # Generate fs.c containing embedded file data
  # Required context:
  #   - gems: Array of gem paths to embed
  #   - ruby_std_libs: Array of Ruby standard library paths to embed
  #   - bundler_config: Path to .bundle/config (if using Gemfile)
  # Dependencies provide:
  #   - WorkDir.path
  #   - CopyProjectFiles.entrypoint_path
  class MakeFsC < Taski::Task
    exports :path

    # File extensions to skip when embedding
    SKIP_EXTENSIONS = %w[
      .so .bundle .c .h .o .java .jar .gz .dat .sqlite3 .exe
      .gem .out .png .jpg .jpeg .gif .bmp .ico .svg .webp .ttf .data
    ].freeze

    # Directory names to prune when traversing
    PRUNE_DIRS = %w[.git ports logs spec .github docs exe _ruby].freeze

    def run
      @work_dir = WorkDir.path
      @path = File.join(@work_dir, "fs.c")

      # Get original paths for Ruby standard library cache support
      # When Ruby is restored from cache, standard library paths are from the original build
      # We need to embed Ruby stdlib files with those original paths so the VFS can find them
      # Project files and gems use current work_dir paths (no replacement needed)
      @original_ruby_install_dir = InstallRuby.original_ruby_install_dir
      @current_ruby_install_dir = InstallRuby.ruby_install_dir

      # Initialize .kompoignore handler
      project_dir = Taski.args.fetch(:project_dir, Taski.env.working_directory) || Taski.env.working_directory
      @kompo_ignore = KompoIgnore.new(project_dir)
      puts "Using .kompoignore from #{project_dir}" if @kompo_ignore.enabled?

      @file_bytes = []
      @paths = []
      @file_sizes = [0]
      @added_paths = Set.new
      @duplicate_count = 0
      @verbose = Taski.args.fetch(:verbose, false)

      group("Collecting files") do
        embed_paths = collect_embed_paths

        embed_paths.each do |embed_path|
          expand_path = File.expand_path(embed_path)
          unless File.exist?(expand_path)
            warn "warn: #{expand_path} does not exist. Skipping."
            next
          end

          if File.directory?(expand_path)
            process_directory(expand_path)
          else
            add_file(expand_path)
          end
        end
        duplicate_info = @duplicate_count.positive? ? " (#{@duplicate_count} duplicates skipped)" : ''
        puts "Collected #{@file_sizes.size - 1} files#{duplicate_info}"
      end

      group("Generating fs.c") do
        context = build_template_context

        template_path = File.join(__dir__, "..", "..", "fs.c.erb")
        template = ERB.new(File.read(template_path))
        File.write(@path, template.result(binding))
        puts "Generated: fs.c (#{@file_bytes.size} bytes)"
      end
    end

    def clean
      return unless @path && File.exist?(@path)

      FileUtils.rm_f(@path)
      puts "Cleaned up fs.c"
    end

    private

    def collect_embed_paths
      paths = []

      # 1. Project files (entrypoint + additional files/directories specified by user)
      #    Created by: CopyProjectFiles
      paths << CopyProjectFiles.entrypoint_path
      paths += CopyProjectFiles.additional_paths

      # 2. Gemfile, Gemfile.lock, and gemspec files (if exists)
      #    Created by: CopyGemfile
      if CopyGemfile.gemfile_exists
        paths << File.join(@work_dir, "Gemfile")
        paths << File.join(@work_dir, "Gemfile.lock")

        # Include gemspec files for Bundler's gemspec directive
        paths += CopyGemfile.gemspec_paths

        # 3. Bundle directory (.bundle/config and bundle/ruby/X.Y.Z/gems/...)
        #    Created by: BundleInstall
        paths << BundleInstall.bundler_config_path
        paths << BundleInstall.bundle_ruby_dir
      end

      # 4. Ruby standard library
      #    Retrieved by: CheckStdlibs
      paths += CheckStdlibs.paths

      paths.compact
    end

    def process_directory(dir_path)
      # Resolve base directory to ensure symlink safety
      real_base = File.realpath(dir_path)

      Find.find(dir_path) do |path|
        # Prune certain directories
        if File.directory?(path)
          base = File.basename(path)
          Find.prune if PRUNE_DIRS.any? { |d| base == d || path.end_with?("/#{d}") }
          next
        end

        # Skip symlinks that escape the base directory (symlink traversal prevention)
        if File.symlink?(path)
          real_path = File.realpath(path)
          unless real_path.start_with?(real_base)
            warn "warn: Skipping symlink escaping base directory: #{path} -> #{real_path}"
            next
          end
        end

        # Skip certain file extensions
        next if SKIP_EXTENSIONS.any? { |ext| path.end_with?(ext) }
        next if path.end_with?("selenium-manager")

        # Skip files matching .kompoignore patterns
        next if should_ignore?(path)

        add_file(path)
      end
    end

    # Check if a file should be ignored based on .kompoignore patterns
    # Only applies to files under work_dir (Ruby standard library is excluded)
    def should_ignore?(absolute_path)
      return false unless @kompo_ignore&.enabled?

      # Only apply .kompoignore to work_dir files (project files and gems)
      # Ruby standard library paths are outside work_dir and should not be filtered
      return false unless absolute_path.start_with?(@work_dir)

      relative_path = absolute_path.sub("#{@work_dir}/", "")
      if @kompo_ignore.ignore?(relative_path)
        puts "Ignoring (via .kompoignore): #{relative_path}"
        true
      else
        false
      end
    end

    def add_file(path)
      # Skip duplicate files (same absolute path)
      if @added_paths.include?(path)
        @duplicate_count += 1
        puts "skip: duplicate path #{path}" if @verbose
        return
      end
      @added_paths.add(path)

      # Keep original paths for VFS - the caching system already ensures
      # the same work_dir path is reused across builds via metadata.json
      # Ruby's $LOAD_PATH uses work_dir paths, so embedded files must match.
      embedded_path = if @current_ruby_install_dir != @original_ruby_install_dir && path.start_with?(@current_ruby_install_dir)
        # Ruby install dir path replacement for cache compatibility (when paths differ)
        path.sub(@current_ruby_install_dir, @original_ruby_install_dir)
      else
        path
      end

      puts "#{path} -> #{embedded_path}" if path != embedded_path

      # Use binread for binary-safe reading (preserves exact bytes without encoding conversion)
      content = File.binread(path)
      bytes = content.bytes
      byte_size = content.bytesize
      path_bytes = embedded_path.bytes << 0 # null-terminated

      file = KompoFile.new(path_bytes, bytes)

      @file_bytes.concat(file.bytes)
      @paths.concat(file.path)
      prev_size = @file_sizes.last
      @file_sizes << (prev_size + byte_size)
    end

    def build_template_context
      FsCTemplateContext.new(
        work_dir: @work_dir
      )
    end

    # Struct for fs.c template variables
    FsCTemplateContext = Struct.new(:work_dir, keyword_init: true)
  end
end
