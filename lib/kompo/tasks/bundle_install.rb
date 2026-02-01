# frozen_string_literal: true

require "fileutils"
require "bundler"
require_relative "../cache/bundle"

module Kompo
  # Run bundle install --path bundle in work directory
  # Uses standard Bundler (not standalone mode) so Bundler.require works
  # Supports caching based on Gemfile.lock hash and Ruby version
  class BundleInstall < Taski::Section
    interfaces :bundle_ruby_dir, :bundler_config_path

    def impl
      # Skip if no Gemfile
      return Skip unless CopyGemfile.gemfile_exists

      # Skip cache if --no-cache is specified
      return FromSource if Taski.args[:no_cache]

      cache_exists? ? FromCache : FromSource
    end

    # Restore bundle from cache
    class FromCache < Taski::Task
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

    # Skip bundle install when no Gemfile
    class Skip < Taski::Task
      def run
        puts "No Gemfile, skipping bundle install"
        @bundle_ruby_dir = nil
        @bundler_config_path = nil
      end

      def clean
      end
    end

    private

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
