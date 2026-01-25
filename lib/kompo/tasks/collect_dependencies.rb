# frozen_string_literal: true

require 'fileutils'

module Kompo
  # Collect all dependencies for packing.
  # This task is used by Packing to get the values it needs.
  class CollectDependencies < Taski::Task
    exports :work_dir, :deps, :ext_paths, :enc_files, :output_path

    Dependencies = Struct.new(
      :ruby_install_dir, :ruby_version, :ruby_major_minor,
      :ruby_build_path, :ruby_lib, :kompo_lib,
      :main_c, :fs_c, :exts_dir, :deps_lib_paths,
      keyword_init: true
    )

    def run
      @work_dir = WorkDir.path
      project_dir = Taski.args.fetch(:project_dir, Taski.env.working_directory) || Taski.env.working_directory
      output_arg = Taski.args.fetch(:output_dir, Taski.env.working_directory) || Taski.env.working_directory

      @deps = group('Collecting dependencies') do
        collect_dependencies
      end

      # If output_arg is an existing directory, create binary inside it
      # Otherwise, treat it as the output file path
      if File.directory?(output_arg)
        @output_path = File.join(output_arg, File.basename(project_dir))
      else
        @output_path = output_arg
        # Ensure parent directory exists
        FileUtils.mkdir_p(File.dirname(@output_path))
      end

      @ext_paths = get_unique_ext_paths(@work_dir, @deps.ruby_build_path, @deps.ruby_version, @deps.exts_dir)
      @enc_files = [
        File.join(@deps.ruby_build_path, "ruby-#{@deps.ruby_version}", 'enc/encinit.o'),
        File.join(@deps.ruby_build_path, "ruby-#{@deps.ruby_version}", 'enc/libenc.a'),
        File.join(@deps.ruby_build_path, "ruby-#{@deps.ruby_version}", 'enc/libtrans.a')
      ]

      puts 'All dependencies collected for packing'
    end

    private

    def collect_dependencies
      # Install dependencies based on platform (Homebrew on macOS, pkg-config check on Linux)
      InstallDeps.run
      deps_lib_paths = InstallDeps.lib_paths

      ruby_install_dir = InstallRuby.ruby_install_dir
      ruby_version = InstallRuby.ruby_version
      ruby_major_minor = InstallRuby.ruby_major_minor
      ruby_build_path = InstallRuby.ruby_build_path
      ruby_lib = File.join(ruby_install_dir, 'lib')

      kompo_lib = KompoVfsPath.path
      main_c = MakeMainC.path
      fs_c = MakeFsC.path
      exts_dir = BuildNativeGem.exts_dir

      puts 'Dependencies collected'

      Dependencies.new(
        ruby_install_dir: ruby_install_dir,
        ruby_version: ruby_version,
        ruby_major_minor: ruby_major_minor,
        ruby_build_path: ruby_build_path,
        ruby_lib: ruby_lib,
        kompo_lib: kompo_lib,
        main_c: main_c,
        fs_c: fs_c,
        exts_dir: exts_dir,
        deps_lib_paths: deps_lib_paths
      )
    end

    def get_unique_ext_paths(_work_dir, ruby_build_path, ruby_version, exts_dir)
      ruby_build_dir = File.join(ruby_build_path, "ruby-#{ruby_version}")

      # Ruby standard extension .o files
      paths = Dir.glob(File.join(ruby_build_dir, 'ext', '**', '*.o'))

      # Ruby bundled gems .o files (Ruby 4.0+)
      # Skip if --no-stdlib is specified (bundled gems are part of stdlib)
      no_stdlib = Taski.args.fetch(:no_stdlib, false)
      unless no_stdlib
        bundled_gems_paths = Dir.glob(File.join(ruby_build_dir, '.bundle', 'gems', '*', 'ext', '**', '*.o'))
        paths += bundled_gems_paths
      end

      # Extract extension path (everything after /ext/) for deduplication
      # e.g., ".../ext/cgi/escape/escape.o" -> "cgi/escape/escape.o"
      ruby_ext_keys = paths.map { |p| p.split('/ext/').last }

      # Gem extension .o files (excluding duplicates with Ruby std)
      if exts_dir && Dir.exist?(exts_dir)
        gem_ext_paths = Dir.glob("#{exts_dir}/**/*.o")
                           .to_h { |p| [p.split('/ext/').last, p] }
                           .except(*ruby_ext_keys)
                           .values
        paths += gem_ext_paths
      end

      paths
    end
  end
end
