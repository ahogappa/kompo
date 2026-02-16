# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Kompo
  # Task to install static Ruby
  # Switches between cache restore and building from source
  # Required context:
  #   - ruby_version: Ruby version to build (default: current RUBY_VERSION)
  #   - kompo_cache: Cache directory for kompo (default: ~/.kompo/cache)
  #   - clear_cache: If true, clear the Ruby build cache before building
  class InstallRuby < Taski::Task
    exports :ruby_path, :bundler_path, :ruby_install_dir, :ruby_version,
      :ruby_major_minor, :ruby_build_path, :original_ruby_install_dir

    def run
      # Skip cache if --no-cache is specified, or if cache doesn't exist
      source = if Taski.args[:no_cache]
        FromSource
      elsif cache_exists?
        FromCache
      else
        FromSource
      end

      @ruby_path = source.ruby_path
      @bundler_path = source.bundler_path
      @ruby_install_dir = source.ruby_install_dir
      @ruby_version = source.ruby_version
      @ruby_major_minor = source.ruby_major_minor
      @ruby_build_path = source.ruby_build_path
      @original_ruby_install_dir = source.original_ruby_install_dir
    end

    # Ruby extensions to build statically
    STATIC_EXTENSIONS = %w[
      bigdecimal
      cgi/escape
      continuation
      coverage
      date
      digest/bubblebabble
      digest
      digest/md5
      digest/rmd160
      digest/sha1
      digest/sha2
      etc
      fcntl
      fiddle
      io/console
      io/nonblock
      io/wait
      json
      json/generator
      json/parser
      nkf
      monitor
      objspace
      openssl
      pathname
      psych
      pty
      racc/cparse
      rbconfig/sizeof
      readline
      ripper
      socket
      stringio
      strscan
      syslog
      zlib
    ].freeze

    # Restore Ruby from cache
    # Uses the work_dir path saved in metadata to ensure $LOAD_PATH matches
    class FromCache < Taski::Task
      exports :ruby_path, :bundler_path, :ruby_install_dir, :ruby_version,
        :ruby_major_minor, :ruby_build_path, :original_ruby_install_dir

      def run
        @ruby_version = Taski.args.fetch(:ruby_version, RUBY_VERSION)
        @ruby_major_minor = ruby_major_and_minor(@ruby_version)

        kompo_cache = Taski.args.fetch(:kompo_cache, File.expand_path("~/.kompo/cache"))
        version_cache_dir = File.join(kompo_cache, @ruby_version)
        cache_install_dir = File.join(version_cache_dir, "ruby")

        # Use WorkDir.path which now automatically uses cached work_dir path
        work_dir = WorkDir.path

        @ruby_install_dir = File.join(work_dir, "_ruby")
        @ruby_path = File.join(@ruby_install_dir, "bin", "ruby")
        @bundler_path = File.join(@ruby_install_dir, "bin", "bundler")
        @ruby_build_path = File.join(@ruby_install_dir, "_build")
        @original_ruby_install_dir = @ruby_install_dir

        group("Restoring Ruby #{@ruby_version} from cache to #{work_dir}") do
          # Clean up existing files in case work_dir is reused
          FileUtils.rm_rf(@ruby_install_dir) if Dir.exist?(@ruby_install_dir)

          # _build directory is included in cache_install_dir
          FileUtils.cp_r(cache_install_dir, @ruby_install_dir)

          puts "Restored from: #{version_cache_dir}"
        end

        # Fix shebangs in bin scripts to point to the new Ruby path
        fix_bin_shebangs(@ruby_install_dir, @ruby_path)

        # Fix ruby.pc prefix to point to the new install directory
        fix_ruby_pc(@ruby_install_dir)

        puts "Ruby #{@ruby_version} restored from cache"
        result = Kompo.command_runner.capture(@ruby_path, "--version", suppress_stderr: true)
        puts "Ruby version: #{result.chomp}"
      end

      def clean
        return unless @ruby_install_dir && Dir.exist?(@ruby_install_dir)

        FileUtils.rm_rf(@ruby_install_dir)
        puts "Cleaned up Ruby installation"
      end

      private

      def ruby_major_and_minor(version)
        parts = version.split(".")
        "#{parts[0]}.#{parts[1]}"
      end

      # Fix shebangs in bin directory to point to the correct Ruby path
      def fix_bin_shebangs(ruby_install_dir, ruby_path)
        bin_dir = File.join(ruby_install_dir, "bin")
        return unless Dir.exist?(bin_dir)

        Dir.glob(File.join(bin_dir, "*")).each do |bin_file|
          next if File.directory?(bin_file)
          next if File.basename(bin_file) == "ruby"

          content = File.read(bin_file)
          next unless content.start_with?("#!")

          # Replace old ruby shebang with new one
          # Handle both direct paths and env-style shebangs, preserving trailing args
          new_content = content.sub(/^#!.*\bruby\b(.*)$/, "#!#{ruby_path}\\1")
          File.write(bin_file, new_content) if new_content != content
        end
      end

      # Fix ruby.pc prefix to match the current install directory
      # This is necessary when restoring from cache because the cached ruby.pc
      # still has the original build directory as prefix
      def fix_ruby_pc(ruby_install_dir)
        ruby_pc_path = File.join(ruby_install_dir, "lib", "pkgconfig", "ruby.pc")
        return unless File.exist?(ruby_pc_path)

        content = File.read(ruby_pc_path)
        new_content = content.sub(/^prefix=.*$/, "prefix=#{ruby_install_dir}")
        File.write(ruby_pc_path, new_content) if new_content != content
      end
    end

    # Build Ruby from source using ruby-build
    # Ruby is built into work_dir with --prefix=work_dir/_ruby.
    # After building, the result is cached with the work_dir path preserved in metadata.
    # When using cache, the same work_dir path is recreated to ensure $LOAD_PATH matches.
    class FromSource < Taski::Task
      exports :ruby_path, :bundler_path, :ruby_install_dir, :ruby_version,
        :ruby_major_minor, :ruby_build_path, :original_ruby_install_dir

      def run
        ruby_build = RubyBuildPath.path

        @ruby_version = Taski.args.fetch(:ruby_version, RUBY_VERSION)
        @ruby_major_minor = ruby_major_and_minor(@ruby_version)

        @kompo_cache = Taski.args.fetch(:kompo_cache, File.expand_path("~/.kompo/cache"))
        @version_cache_dir = File.join(@kompo_cache, @ruby_version)

        # Check if we have a valid cache (skip if --no-cache is specified)
        cache_metadata_path = File.join(@version_cache_dir, "metadata.json")
        if !Taski.args[:no_cache] && cache_valid?(cache_metadata_path)
          restore_from_cache(cache_metadata_path)
        else
          build_and_cache(ruby_build)
        end

        puts "Ruby installed at: #{@ruby_install_dir}"
        result = Kompo.command_runner.capture(@ruby_path, "--version", suppress_stderr: true)
        puts "Ruby version: #{result.chomp}"
      end

      def clean
        return unless @ruby_install_dir && Dir.exist?(@ruby_install_dir)

        FileUtils.rm_rf(@ruby_install_dir)
        puts "Cleaned up Ruby installation"
      end

      private

      def cache_valid?(metadata_path)
        return false unless File.exist?(metadata_path)

        metadata = JSON.parse(File.read(metadata_path))
        cached_work_dir = metadata["work_dir"]
        cache_install_dir = File.join(@version_cache_dir, "ruby")

        cached_work_dir && Dir.exist?(cache_install_dir)
      rescue JSON::ParserError
        false
      end

      def restore_from_cache(_metadata_path)
        # Use WorkDir.path which now automatically uses cached work_dir path
        work_dir = WorkDir.path

        @ruby_install_dir = File.join(work_dir, "_ruby")
        @ruby_path = File.join(@ruby_install_dir, "bin", "ruby")
        @bundler_path = File.join(@ruby_install_dir, "bin", "bundler")
        @ruby_build_path = File.join(@ruby_install_dir, "_build")
        @original_ruby_install_dir = @ruby_install_dir

        cache_install_dir = File.join(@version_cache_dir, "ruby")

        group("Restoring Ruby from cache to #{work_dir}") do
          # Clean up existing files in case work_dir is reused
          FileUtils.rm_rf(@ruby_install_dir) if Dir.exist?(@ruby_install_dir)

          # _build directory is included in cache_install_dir
          FileUtils.cp_r(cache_install_dir, @ruby_install_dir)
        end

        # Fix shebangs in bin scripts to point to the new Ruby path
        fix_bin_shebangs(@ruby_install_dir, @ruby_path)

        # Fix ruby.pc prefix to point to the new install directory
        fix_ruby_pc(@ruby_install_dir)
      end

      def build_and_cache(ruby_build)
        work_dir = WorkDir.path

        # Build Ruby into work_dir with prefix pointing to work_dir
        @ruby_install_dir = File.join(work_dir, "_ruby")
        @ruby_path = File.join(@ruby_install_dir, "bin", "ruby")
        @bundler_path = File.join(@ruby_install_dir, "bin", "bundler")
        @ruby_build_path = File.join(@ruby_install_dir, "_build")
        @original_ruby_install_dir = @ruby_install_dir

        # Handle custom Ruby source
        ruby_source_path = Taski.args[:ruby_source_path]
        ruby_definition = prepare_ruby_source(ruby_source_path)

        # Check if the Ruby version is available in ruby-build (only if not using custom source)
        check_ruby_version_availability(ruby_build) unless ruby_source_path

        configure_opts = build_configure_opts(@ruby_install_dir)

        command = [
          ruby_build,
          "--verbose",
          "--keep",
          ruby_definition,
          @ruby_install_dir
        ]

        group("Building Ruby #{@ruby_version} in #{work_dir}") do
          FileUtils.mkdir_p(@version_cache_dir)
          # Pass configuration via environment variables required by ruby-build
          env = {
            "RUBY_CONFIGURE_OPTS" => configure_opts,
            "RUBY_BUILD_CACHE_PATH" => @version_cache_dir,
            "RUBY_BUILD_BUILD_PATH" => @ruby_build_path
          }
          # Clear Bundler environment to prevent interference with ruby-build
          # This is necessary because ruby-build's make install runs rbinstall.rb,
          # which loads rubygems, which loads bundler if BUNDLE_GEMFILE is set.
          Bundler.with_unbundled_env do
            Kompo.command_runner.run(*command, env: env, error_message: "Failed to build Ruby")
          end
        end

        # Save to cache after successful build
        save_to_cache(work_dir)
      end

      def save_to_cache(work_dir)
        return if Taski.args[:no_cache]

        cache_install_dir = File.join(@version_cache_dir, "ruby")

        group("Saving Ruby to cache") do
          # Remove old cache if exists
          FileUtils.rm_rf(cache_install_dir) if Dir.exist?(cache_install_dir)

          # Copy to cache
          # Note: _build directory is included in @ruby_install_dir
          FileUtils.cp_r(@ruby_install_dir, cache_install_dir)

          # Save metadata with work_dir path
          metadata = {
            "work_dir" => work_dir,
            "ruby_version" => @ruby_version,
            "created_at" => Time.now.iso8601
          }
          File.write(File.join(@version_cache_dir, "metadata.json"), JSON.pretty_generate(metadata))
        end
      end

      # Prepare Ruby source for building
      # @param source_path [String, nil] Path to Ruby source (tarball or directory)
      # @return [String] ruby-build definition (version or source path)
      def prepare_ruby_source(source_path)
        return @ruby_version unless source_path

        raise "Ruby source path does not exist: #{source_path}" unless File.exist?(source_path)

        if File.directory?(source_path)
          # Directory: use it directly as ruby-build definition
          puts "Using Ruby source directory: #{source_path}"
          source_path
        elsif source_path.end_with?(".tar.gz", ".tgz")
          # Extract version from tarball filename
          tarball_version = extract_version_from_tarball(source_path)

          # Check for version mismatch if --ruby-version was explicitly specified
          user_specified_version = Taski.args[:ruby_version]
          if user_specified_version && tarball_version && user_specified_version != tarball_version
            raise "Version mismatch: --ruby-version=#{user_specified_version} but tarball is ruby-#{tarball_version}.tar.gz. " \
                  "Please use matching versions or omit --ruby-version to use the tarball version."
          end

          # Use tarball version if available, otherwise fall back to @ruby_version
          effective_version = tarball_version || @ruby_version
          @ruby_version = effective_version
          @ruby_major_minor = ruby_major_and_minor(effective_version)

          # Update cache directory for new version
          @version_cache_dir = File.join(@kompo_cache, effective_version)

          # Tarball: copy to version cache directory with expected name for ruby-build
          FileUtils.mkdir_p(@version_cache_dir)
          target_tarball = File.join(@version_cache_dir, "ruby-#{effective_version}.tar.gz")
          unless File.expand_path(source_path) == File.expand_path(target_tarball)
            FileUtils.cp(source_path, target_tarball)
            puts "Copied Ruby tarball to: #{target_tarball}"
          end
          puts "Using Ruby version from tarball: #{effective_version}"
          effective_version
        else
          raise "Unsupported source format: #{source_path}. Expected .tar.gz file or directory."
        end
      end

      # Extract Ruby version from tarball filename
      # @param path [String] Path to tarball (e.g., /path/to/ruby-3.4.1.tar.gz)
      # @return [String, nil] Version string or nil if not found
      def extract_version_from_tarball(path)
        filename = File.basename(path)
        return unless filename =~ /^ruby-(\d+\.\d+\.\d+(?:-\w+)?)(?:\.tar)?\.(?:gz|tgz)$/

        ::Regexp.last_match(1)
      end

      def build_configure_opts(install_dir)
        [
          "--prefix=#{install_dir}",
          "--disable-install-doc",
          "--disable-install-rdoc",
          "--disable-install-capi",
          "--with-static-linked-ext",
          "--with-ruby-pc=ruby.pc",
          "--with-ext=#{STATIC_EXTENSIONS.join(",")}",
          "--disable-shared"
        ].join(" ")
      end

      def check_ruby_version_availability(ruby_build)
        result = Kompo.command_runner.capture(ruby_build, "--definitions", suppress_stderr: true)
        available_versions = result.success? ? result.output.split("\n").map(&:strip) : []

        return if available_versions.include?(@ruby_version)

        similar_versions = available_versions.select { |v| v.start_with?(@ruby_version.split(".")[0..1].join(".")) }
        error_message = "Ruby #{@ruby_version} is not available in ruby-build.\n"
        error_message += "Available similar versions: #{similar_versions.join(", ")}\n" unless similar_versions.empty?
        error_message += "Try updating ruby-build or use --ruby-version to specify a different version."
        raise error_message
      end

      def ruby_major_and_minor(version)
        parts = version.split(".")
        "#{parts[0]}.#{parts[1]}"
      end

      # Fix shebangs in bin directory to point to the correct Ruby path
      def fix_bin_shebangs(ruby_install_dir, ruby_path)
        bin_dir = File.join(ruby_install_dir, "bin")
        return unless Dir.exist?(bin_dir)

        Dir.glob(File.join(bin_dir, "*")).each do |bin_file|
          next if File.directory?(bin_file)
          next if File.basename(bin_file) == "ruby"

          content = File.read(bin_file)
          next unless content.start_with?("#!")

          # Replace old ruby shebang with new one
          # Handle both direct paths and env-style shebangs, preserving trailing args
          new_content = content.sub(/^#!.*\bruby\b(.*)$/, "#!#{ruby_path}\\1")
          File.write(bin_file, new_content) if new_content != content
        end
      end

      # Fix ruby.pc prefix to match the current install directory
      # This is necessary when restoring from cache because the cached ruby.pc
      # still has the original build directory as prefix
      def fix_ruby_pc(ruby_install_dir)
        ruby_pc_path = File.join(ruby_install_dir, "lib", "pkgconfig", "ruby.pc")
        return unless File.exist?(ruby_pc_path)

        content = File.read(ruby_pc_path)
        new_content = content.sub(/^prefix=.*$/, "prefix=#{ruby_install_dir}")
        File.write(ruby_pc_path, new_content) if new_content != content
      end
    end

    private

    def cache_exists?
      ruby_version = Taski.args.fetch(:ruby_version, RUBY_VERSION)
      kompo_cache = Taski.args.fetch(:kompo_cache, File.expand_path("~/.kompo/cache"))
      version_cache_dir = File.join(kompo_cache, ruby_version)

      cache_install_dir = File.join(version_cache_dir, "ruby")
      cache_metadata = File.join(version_cache_dir, "metadata.json")

      Dir.exist?(cache_install_dir) && File.exist?(cache_metadata)
    end
  end
end
