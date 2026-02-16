# frozen_string_literal: true

module Kompo
  # Get Ruby standard library paths from installed Ruby
  class CheckStdlibs < Taski::Task
    exports :paths

    def run
      # Check if stdlib should be excluded
      no_stdlib = Taski.args.fetch(:no_stdlib, false)
      if no_stdlib
        @paths = []
        puts "Skipping standard library (--no-stdlib)"
        return
      end

      ruby = InstallRuby.ruby_path
      ruby_install_dir = InstallRuby.ruby_install_dir
      original_ruby_install_dir = InstallRuby.original_ruby_install_dir
      ruby_major_minor = InstallRuby.ruby_major_minor

      # Include the Ruby standard library root directory
      # This includes bundler and other default gems that are not in $:
      # Ruby uses "X.Y.0" format for lib/ruby paths (e.g., "3.4.0" not "3.4")
      stdlib_root = File.join(ruby_install_dir, "lib", "ruby", "#{ruby_major_minor}.0")
      # RubyGems needs gemspec files in specifications/ directory
      gems_root = File.join(ruby_install_dir, "lib", "ruby", "gems", "#{ruby_major_minor}.0")
      gems_specs_root = File.join(gems_root, "specifications")

      if Dir.exist?(stdlib_root)
        @paths = [stdlib_root, gems_specs_root].select { |p| Dir.exist?(p) }

        # Include installed bundler gem directory (installed by BundleInstall to match Gemfile.lock)
        bundler_gem_dirs = Dir.glob(File.join(gems_root, "gems", "bundler-*"))
        bundler_gem_dirs.each do |dir|
          @paths << dir
          puts "Including bundler gem: #{dir}"
        end

        puts "Including Ruby standard library: #{stdlib_root}"
        puts "Including gem specifications: #{gems_specs_root}" if Dir.exist?(gems_specs_root)
      else
        # Fallback to $: paths if stdlib root doesn't exist
        result = Kompo.command_runner.capture(ruby, "-e", "puts $:", suppress_stderr: true)
        unless result.success?
          raise "Failed to get Ruby standard library paths: exit code #{result.exit_code}, output: #{result.output}"
        end

        raw_paths = result.output.split("\n").reject(&:empty?)

        @paths = raw_paths.map do |path|
          next nil unless path.start_with?("/")

          if original_ruby_install_dir != ruby_install_dir && path.start_with?(original_ruby_install_dir)
            path.sub(original_ruby_install_dir, ruby_install_dir)
          else
            path
          end
        end.compact

        puts "Found #{@paths.size} standard library paths (fallback)"
      end
    end
  end
end
