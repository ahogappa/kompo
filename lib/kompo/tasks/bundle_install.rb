# frozen_string_literal: true

require 'fileutils'
require 'digest'
require 'json'
require 'bundler'

module Kompo
  # Shared helpers for bundle cache operations
  module BundleCacheHelpers
    private

    def compute_bundle_cache_name
      hash = compute_gemfile_lock_hash
      return nil unless hash

      "bundle-#{hash}"
    end

    def compute_gemfile_lock_hash
      work_dir = WorkDir.path
      gemfile_lock_path = File.join(work_dir, 'Gemfile.lock')
      return nil unless File.exist?(gemfile_lock_path)

      content = File.read(gemfile_lock_path)
      Digest::SHA256.hexdigest(content)[0..15]
    end
  end

  # Run bundle install --path bundle in work directory
  # Uses standard Bundler (not standalone mode) so Bundler.require works
  # Supports caching based on Gemfile.lock hash and Ruby version
  class BundleInstall < Taski::Section
    include BundleCacheHelpers

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
      include BundleCacheHelpers

      def run
        work_dir = WorkDir.path
        ruby_major_minor = InstallRuby.ruby_major_minor

        @bundle_ruby_dir = File.join(work_dir, 'bundle', 'ruby', "#{ruby_major_minor}.0")
        @bundler_config_path = File.join(work_dir, '.bundle', 'config')

        kompo_cache = Taski.args.fetch(:kompo_cache, File.expand_path('~/.kompo/cache'))
        ruby_version = InstallRuby.ruby_version
        version_cache_dir = File.join(kompo_cache, ruby_version)

        bundle_cache_name = compute_bundle_cache_name
        raise "Gemfile.lock not found in #{work_dir}" unless bundle_cache_name

        cache_dir = File.join(version_cache_dir, bundle_cache_name)

        group('Restoring bundle from cache') do
          # Clean up existing files in case work_dir is reused
          FileUtils.rm_rf(File.join(work_dir, 'bundle')) if Dir.exist?(File.join(work_dir, 'bundle'))
          FileUtils.rm_rf(File.join(work_dir, '.bundle')) if Dir.exist?(File.join(work_dir, '.bundle'))

          # Copy from cache
          FileUtils.cp_r(File.join(cache_dir, 'bundle'), File.join(work_dir, 'bundle'))
          FileUtils.cp_r(File.join(cache_dir, '.bundle'), File.join(work_dir, '.bundle'))

          puts "Restored from: #{cache_dir}"
        end

        puts 'Bundle restored from cache'
      end

      def clean
        work_dir = WorkDir.path
        return unless work_dir && Dir.exist?(work_dir)

        [@bundle_ruby_dir, @bundler_config_path].each do |path|
          next unless path

          FileUtils.rm_rf(path) if File.exist?(path)
        end
        puts 'Cleaned up bundle installation'
      end
    end

    # Run bundle install and save to cache
    class FromSource < Taski::Task
      include BundleCacheHelpers

      def run
        work_dir = WorkDir.path
        bundler = InstallRuby.bundler_path
        ruby_major_minor = InstallRuby.ruby_major_minor

        @bundle_ruby_dir = File.join(work_dir, 'bundle', 'ruby', "#{ruby_major_minor}.0")
        @bundler_config_path = File.join(work_dir, '.bundle', 'config')

        puts 'Running bundle install --path bundle...'
        gemfile_path = File.join(work_dir, 'Gemfile')

        # Clear Bundler environment and specify Gemfile path explicitly
        Bundler.with_unbundled_env do
          ruby = InstallRuby.ruby_path
          env = { 'BUNDLE_GEMFILE' => gemfile_path }

          # Suppress clang 18+ warning that causes mkmf try_cppflags to fail
          # This flag is clang-specific and not recognized by GCC
          if clang_compiler?
            env['CFLAGS'] = '-Wno-default-const-init-field-unsafe'
            env['CPPFLAGS'] = '-Wno-default-const-init-field-unsafe'
          end

          # Set BUNDLE_PATH to "bundle" - standard Bundler reads .bundle/config
          # and finds gems in {BUNDLE_PATH}/ruby/X.X.X/gems/
          # Use ruby to execute bundler to avoid shebang issues
          system({ 'BUNDLE_GEMFILE' => gemfile_path }, ruby, bundler, 'config', 'set', '--local', 'path',
                 'bundle') or raise 'Failed to set bundle path'
          system(env, ruby, bundler, 'install') or raise 'Failed to run bundle install'
        end

        puts 'Bundle installed successfully'

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
        puts 'Cleaned up bundle installation'
      end

      private

      def clang_compiler?
        output = `cc --version 2>&1`
        output.include?('clang')
      rescue Errno::ENOENT => e
        warn "cc command not found: #{e.message}"
        false
      rescue StandardError => e
        warn "Error checking compiler: #{e.message}"
        false
      end

      def save_to_cache(work_dir)
        bundle_cache_name = compute_bundle_cache_name
        return unless bundle_cache_name

        kompo_cache = Taski.args.fetch(:kompo_cache, File.expand_path('~/.kompo/cache'))
        ruby_version = InstallRuby.ruby_version
        version_cache_dir = File.join(kompo_cache, ruby_version)
        cache_dir = File.join(version_cache_dir, bundle_cache_name)

        group('Saving bundle to cache') do
          # Remove old cache if exists
          FileUtils.rm_rf(cache_dir) if Dir.exist?(cache_dir)
          FileUtils.mkdir_p(cache_dir)

          # Copy to cache
          FileUtils.cp_r(File.join(work_dir, 'bundle'), File.join(cache_dir, 'bundle'))
          FileUtils.cp_r(File.join(work_dir, '.bundle'), File.join(cache_dir, '.bundle'))

          # Save metadata
          metadata = {
            'ruby_version' => ruby_version,
            'gemfile_lock_hash' => compute_gemfile_lock_hash,
            'created_at' => Time.now.iso8601
          }
          File.write(File.join(cache_dir, 'metadata.json'), JSON.pretty_generate(metadata))

          puts "Saved to: #{cache_dir}"
        end
      end
    end

    # Skip bundle install when no Gemfile
    class Skip < Taski::Task
      def run
        puts 'No Gemfile, skipping bundle install'
        @bundle_ruby_dir = nil
        @bundler_config_path = nil
      end

      def clean
        # Nothing to clean
      end
    end

    private

    def cache_exists?
      bundle_cache_name = compute_bundle_cache_name
      return false unless bundle_cache_name

      kompo_cache = Taski.args.fetch(:kompo_cache, File.expand_path('~/.kompo/cache'))
      ruby_version = InstallRuby.ruby_version
      version_cache_dir = File.join(kompo_cache, ruby_version)
      cache_dir = File.join(version_cache_dir, bundle_cache_name)

      cache_bundle_dir = File.join(cache_dir, 'bundle')
      cache_bundle_config = File.join(cache_dir, '.bundle')
      cache_metadata = File.join(cache_dir, 'metadata.json')

      Dir.exist?(cache_bundle_dir) && Dir.exist?(cache_bundle_config) && File.exist?(cache_metadata)
    end
  end
end
