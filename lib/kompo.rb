# frozen_string_literal: true

require 'taski'
require_relative 'kompo/version'

module Kompo
  # Fixed path prefix for Ruby installation
  # Using a fixed path ensures that cached Ruby binaries work correctly,
  # since Ruby has hardcoded paths for standard library locations.
  KOMPO_PREFIX = '/kompo'

  # Utility classes
  autoload :KompoIgnore, 'kompo/kompo_ignore'

  # Struct to hold file data for embedding (used by MakeFsC)
  autoload :KompoFile, 'kompo/tasks/make_fs_c'

  # Core tasks
  autoload :WorkDir, 'kompo/tasks/work_dir'
  autoload :CopyProjectFiles, 'kompo/tasks/copy_project_files'
  autoload :CopyGemfile, 'kompo/tasks/copy_gemfile'
  autoload :MakeMainC, 'kompo/tasks/make_main_c'
  autoload :MakeFsC, 'kompo/tasks/make_fs_c'

  # Ruby installation
  autoload :InstallRuby, 'kompo/tasks/install_ruby'
  autoload :CheckStdlibs, 'kompo/tasks/check_stdlibs'

  # Bundle and gem tasks
  autoload :BundleInstall, 'kompo/tasks/bundle_install'
  autoload :FindNativeExtensions, 'kompo/tasks/find_native_extensions'
  autoload :BuildNativeGem, 'kompo/tasks/build_native_gem'

  # Final packing (Section: macOS uses clang, Linux uses gcc)
  autoload :CollectDependencies, 'kompo/tasks/collect_dependencies'
  autoload :Packing, 'kompo/tasks/packing'

  # Homebrew path (macOS)
  autoload :HomebrewPath, 'kompo/tasks/homebrew'

  # Platform-specific dependencies (Section: macOS uses Homebrew, Linux checks via pkg-config)
  autoload :InstallDeps, 'kompo/tasks/install_deps'

  # External tool paths
  autoload :KompoVfsPath, 'kompo/tasks/kompo_vfs_path'
  autoload :KompoVfsVersionCheck, 'kompo/tasks/kompo_vfs_version_check'
  autoload :RubyBuildPath, 'kompo/tasks/ruby_build_path'
  autoload :CargoPath, 'kompo/tasks/cargo_path'
end

# Load cache methods (module methods, not autoloadable)
require_relative 'kompo/cache'
