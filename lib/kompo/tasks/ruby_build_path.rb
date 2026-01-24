# frozen_string_literal: true

require 'open3'

module Kompo
  # Section to get the ruby-build path.
  # Switches implementation based on whether ruby-build is already installed.
  class RubyBuildPath < Taski::Section
    interfaces :path

    def impl
      ruby_build_installed? ? Installed : Install
    end

    # Use existing ruby-build installation
    class Installed < Taski::Task
      def run
        path_output, = Open3.capture2('which', 'ruby-build', err: File::NULL)
        @path = path_output.chomp
        puts "ruby-build path: #{@path}"
        version_output, = Open3.capture2(@path, '--version', err: File::NULL)
        puts "ruby-build version: #{version_output.chomp}"
      end
    end

    # Install ruby-build via git clone and return the path
    class Install < Taski::Task
      def run
        puts 'ruby-build not found. Installing via git...'
        install_dir = File.expand_path('~/.ruby-build')

        if Dir.exist?(install_dir)
          system('git', '-C', install_dir, 'pull', '--quiet')
        else
          system('git', 'clone', 'https://github.com/rbenv/ruby-build.git', install_dir)
        end

        @path = File.join(install_dir, 'bin', 'ruby-build')
        raise 'Failed to install ruby-build' unless File.executable?(@path)

        puts "ruby-build installed at: #{@path}"
        version_output, = Open3.capture2(@path, '--version', err: File::NULL)
        puts "ruby-build version: #{version_output.chomp}"
      end
    end

    private

    def ruby_build_installed?
      _, status = Open3.capture2('which', 'ruby-build', err: File::NULL)
      status.success?
    end
  end
end
