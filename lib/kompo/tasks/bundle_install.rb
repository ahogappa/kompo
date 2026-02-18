# frozen_string_literal: true

require "fileutils"
require "bundler"
require_relative "../cache/bundle"

module Kompo
  # Run bundle install --path bundle in work directory
  # Uses standard Bundler (not standalone mode) so Bundler.require works
  # Supports caching based on Gemfile.lock hash and Ruby version
  class BundleInstall < Taski::Task
    exports :bundle_ruby_dir, :bundler_config_path

    def run
      # Skip if no Gemfile
      unless CopyGemfile.gemfile_exists
        puts "No Gemfile, skipping bundle install"
        return
      end

      # Install matching bundler version as default gem before bundle install
      install_matching_bundler

      # Skip cache if --no-cache is specified
      if Taski.args[:no_cache]
        @bundle_ruby_dir = FromSource.bundle_ruby_dir
        @bundler_config_path = FromSource.bundler_config_path
        return
      end

      if cache_exists?
        @bundle_ruby_dir = FromCache.bundle_ruby_dir
        @bundler_config_path = FromCache.bundler_config_path
      else
        @bundle_ruby_dir = FromSource.bundle_ruby_dir
        @bundler_config_path = FromSource.bundler_config_path
      end
    end

    # Restore bundle from cache
    class FromCache < Taski::Task
      exports :bundle_ruby_dir, :bundler_config_path

      def run
        work_dir = WorkDir.path
        ruby_major_minor = InstallRuby.ruby_major_minor

        @bundle_ruby_dir = File.join(work_dir, "bundle", "ruby", "#{ruby_major_minor}.0")
        @bundler_config_path = File.join(work_dir, ".bundle", "config")

        cache_dir = Taski.args.fetch(:cache_dir, DEFAULT_CACHE_DIR)
        ruby_version = InstallRuby.ruby_version

        bundle_cache = BundleCache.from_work_dir(
          cache_dir: cache_dir,
          ruby_version: ruby_version,
          work_dir: work_dir
        )
        raise "Gemfile.lock not found in #{work_dir}" unless bundle_cache

        group("Restoring bundle from cache") do
          bundle_cache.restore(work_dir)
          puts "Restored from: #{bundle_cache.cache_dir}"
        end

        puts "Bundle restored from cache"
      end

      def clean
        work_dir = WorkDir.path
        return unless work_dir && Dir.exist?(work_dir)

        [@bundle_ruby_dir, @bundler_config_path].each do |path|
          next unless path

          FileUtils.rm_rf(path) if File.exist?(path)
        end
        puts "Cleaned up bundle installation"
      end
    end

    # Run bundle install and save to cache
    class FromSource < Taski::Task
      exports :bundle_ruby_dir, :bundler_config_path

      def run
        work_dir = WorkDir.path
        bundler = InstallRuby.bundler_path
        ruby_major_minor = InstallRuby.ruby_major_minor

        @bundle_ruby_dir = File.join(work_dir, "bundle", "ruby", "#{ruby_major_minor}.0")
        @bundler_config_path = File.join(work_dir, ".bundle", "config")

        puts "Running bundle install --path bundle..."
        gemfile_path = File.join(work_dir, "Gemfile")

        # Clear Bundler environment and specify Gemfile path explicitly
        Bundler.with_unbundled_env do
          ruby = InstallRuby.ruby_path

          env = {"BUNDLE_GEMFILE" => gemfile_path}

          # Suppress clang 18+ warning that causes mkmf try_cppflags to fail
          # This flag is clang-specific and not recognized by GCC
          if clang_compiler?
            env["CFLAGS"] = "-Wno-default-const-init-field-unsafe"
            env["CPPFLAGS"] = "-Wno-default-const-init-field-unsafe"
          end

          # Set BUNDLE_PATH to "bundle" - standard Bundler reads .bundle/config
          # and finds gems in {BUNDLE_PATH}/ruby/X.X.X/gems/
          # Use ruby to execute bundler to avoid shebang issues
          Kompo.command_runner.run(
            ruby, bundler, "config", "set", "--local", "path", "bundle",
            env: {"BUNDLE_GEMFILE" => gemfile_path},
            error_message: "Failed to set bundle path"
          )
          Kompo.command_runner.run(
            ruby, bundler, "install",
            env: env,
            error_message: "Failed to run bundle install"
          )
        end

        puts "Bundle installed successfully"

        # Save to cache
        save_to_cache(work_dir)
      end

      def clean
        work_dir = WorkDir.path
        return unless work_dir && Dir.exist?(work_dir)

        [@bundle_ruby_dir, @bundler_config_path].each do |path|
          next unless path

          FileUtils.rm_rf(path) if File.exist?(path)
        end
        puts "Cleaned up bundle installation"
      end

      private

      def clang_compiler?
        result = Kompo.command_runner.capture_all("cc", "--version")
        result.output.include?("clang")
      rescue => e
        warn "Error checking compiler: #{e.message}"
        false
      end

      def save_to_cache(work_dir)
        return if Taski.args[:no_cache]

        cache_dir = Taski.args.fetch(:cache_dir, DEFAULT_CACHE_DIR)
        ruby_version = InstallRuby.ruby_version

        bundle_cache = BundleCache.from_work_dir(
          cache_dir: cache_dir,
          ruby_version: ruby_version,
          work_dir: work_dir
        )
        return unless bundle_cache

        group("Saving bundle to cache") do
          bundle_cache.save(work_dir)
          puts "Saved to: #{bundle_cache.cache_dir}"
        end
      end
    end

    private

    def install_matching_bundler
      work_dir = WorkDir.path
      gemfile_lock_path = File.join(work_dir, "Gemfile.lock")
      return unless File.exist?(gemfile_lock_path)

      locked_version = parse_bundled_with(gemfile_lock_path)
      return unless locked_version

      ruby = InstallRuby.ruby_path
      result = Bundler.with_unbundled_env do
        Kompo.command_runner.capture(
          ruby, "-e", "require 'bundler'; puts Bundler::VERSION",
          suppress_stderr: true
        )
      end
      current_version = result.chomp

      return if current_version == locked_version

      puts "Installing bundler #{locked_version} (current: #{current_version})..."
      gem_path = File.join(InstallRuby.ruby_install_dir, "bin", "gem")
      Bundler.with_unbundled_env do
        Kompo.command_runner.run(
          ruby, gem_path, "install", "bundler", "-v", locked_version,
          error_message: "Failed to install bundler #{locked_version}"
        )
      end
    end

    BUNDLER_VERSION_PATTERN = /\A\d+\.\d+(\.\d+)*([.-][a-zA-Z0-9.]+)*\z/

    def parse_bundled_with(gemfile_lock_path)
      lines = File.readlines(gemfile_lock_path)
      bundled_with_index = lines.index { |l| l.strip == "BUNDLED WITH" }
      return unless bundled_with_index

      version = lines[bundled_with_index + 1]&.strip
      return if version.nil? || version.empty?
      return unless BUNDLER_VERSION_PATTERN.match?(version)

      version
    end

    def cache_exists?
      cache_dir = Taski.args.fetch(:cache_dir, DEFAULT_CACHE_DIR)
      ruby_version = InstallRuby.ruby_version
      work_dir = WorkDir.path

      bundle_cache = BundleCache.from_work_dir(
        cache_dir: cache_dir,
        ruby_version: ruby_version,
        work_dir: work_dir
      )
      return false unless bundle_cache

      bundle_cache.exists?
    end
  end
end
