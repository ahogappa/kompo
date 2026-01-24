# frozen_string_literal: true

require 'open3'

module Kompo
  # Get Ruby standard library paths from installed Ruby
  class CheckStdlibs < Taski::Task
    exports :paths

    def run
      # Check if stdlib should be excluded
      no_stdlib = Taski.args.fetch(:no_stdlib, false)
      if no_stdlib
        @paths = []
        puts 'Skipping standard library (--no-stdlib)'
        return
      end

      ruby = InstallRuby.ruby_path
      ruby_install_dir = InstallRuby.ruby_install_dir
      original_ruby_install_dir = InstallRuby.original_ruby_install_dir
      ruby_major_minor = InstallRuby.ruby_major_minor

      # Include the Ruby standard library root directory
      # This includes bundler and other default gems that are not in $:
      # Ruby uses "X.Y.0" format for lib/ruby paths (e.g., "3.4.0" not "3.4")
      stdlib_root = File.join(ruby_install_dir, 'lib', 'ruby', "#{ruby_major_minor}.0")
      # RubyGems needs gemspec files in specifications/ directory
      gems_specs_root = File.join(ruby_install_dir, 'lib', 'ruby', 'gems', "#{ruby_major_minor}.0", 'specifications')

      if Dir.exist?(stdlib_root)
        @paths = [stdlib_root, gems_specs_root].select { |p| Dir.exist?(p) }
        puts "Including Ruby standard library: #{stdlib_root}"
        puts "Including gem specifications: #{gems_specs_root}" if Dir.exist?(gems_specs_root)
      else
        # Fallback to $: paths if stdlib root doesn't exist
        output, status = Open3.capture2(ruby, '-e', 'puts $:', err: File::NULL)
        unless status.success?
          raise "Failed to get Ruby standard library paths: exit code #{status.exitstatus}, output: #{output}"
        end

        raw_paths = output.split("\n").reject(&:empty?)

        @paths = raw_paths.map do |path|
          next nil unless path.start_with?('/')

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
