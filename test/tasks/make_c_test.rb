# frozen_string_literal: true

require_relative "../test_helper"

class MakeMainCTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_make_main_c_generates_file
    with_tmpdir do |tmpdir|
      tmpdir << "work/"
      work_dir = File.join(tmpdir, "work")
      main_c_path = File.join(work_dir, "main.c")
      entrypoint = File.join(work_dir, "main.rb")

      mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
      mock_task(Kompo::CopyProjectFiles, entrypoint_path: entrypoint, additional_paths: [])
      mock_task(Kompo::BuildNativeGem, exts: [], exts_dir: nil)
      mock_task(Kompo::CopyGemfile, gemfile_exists: false)
      mock_task(Kompo::FindNativeExtensions, extensions: [])
      mock_task(Kompo::InstallRuby,
        ruby_version: "3.4.1",
        ruby_build_path: "/path/to/build",
        ruby_path: "/path/to/ruby",
        ruby_install_dir: "/path/to/install",
        original_ruby_install_dir: "/path/to/install",
        ruby_major_minor: "3.4")
      mock_task(Kompo::BundleInstall,
        bundle_ruby_dir: nil,
        bundler_config_path: nil)

      path = Kompo::MakeMainC.path

      assert_equal main_c_path, path
      assert File.exist?(main_c_path), "main.c should be generated"
      content = File.read(main_c_path)
      assert_includes content, "ruby_init"
    end
  end
end

class MakeFsCTest < Minitest::Test
  include Taski::TestHelper::Minitest
  include TaskTestHelpers

  def test_make_fs_c_generates_file
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint)

      path = Kompo::MakeFsC.path

      assert_equal File.join(work_dir, "fs.c"), path
      assert File.exist?(path), "fs.c should be generated"
      content = File.read(path)
      assert_includes content, "const char FILES[]"
      assert_includes content, "const char PATHS[]"
    end
  end

  def test_make_fs_c_with_additional_paths
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      tmpdir << ["work/lib/app.rb", "class App; end"]
      lib_dir = File.join(work_dir, "lib")

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint, additional_paths: [lib_dir])

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
      assert_includes File.read(path), "const char FILES[]"
    end
  end

  def test_make_fs_c_prunes_git_directories
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      tmpdir << ["work/lib/app.rb", "class App; end"] \
             << ["work/lib/.git/config", "git config"]
      lib_dir = File.join(work_dir, "lib")

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint, additional_paths: [lib_dir])

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
      refute_includes File.read(path), "git config"
    end
  end

  def test_make_fs_c_handles_nonexistent_path
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint, additional_paths: ["/nonexistent/path"])

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
    end
  end

  def test_make_fs_c_skips_binary_extensions
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      tmpdir << ["work/test.so", "binary"] \
             << ["work/test.o", "object"] \
             << ["work/image.png", "image"]

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint)

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
    end
  end

  def test_make_fs_c_with_gemfile
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir, content: "require 'bundler/setup'")
      tmpdir << "work/bundle/ruby/3.4.0/" \
             << ["work/.bundle/config", "BUNDLE_PATH: bundle"] \
             << ["work/Gemfile", "source 'https://rubygems.org'"] \
             << ["work/Gemfile.lock", "GEM\n  specs:\n"]

      bundle_dir = File.join(work_dir, "bundle", "ruby", "3.4.0")
      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint,
        gemfile_exists: true,
        bundler_config_path: File.join(work_dir, ".bundle", "config"),
        bundle_ruby_dir: bundle_dir)

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
    end
  end

  def test_make_fs_c_with_kompoignore
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      tmpdir << ["project/.kompoignore", "*.log\ntmp/"]
      project_dir = File.join(tmpdir, "project")

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint)

      path = Kompo::MakeFsC.path(args: {project_dir: project_dir})

      assert File.exist?(path)
    end
  end

  def test_make_fs_c_ignores_files_matching_kompoignore
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      tmpdir << ["work/debug.log", "DEBUG LOG CONTENT"] \
             << ["work/tmp/cache.txt", "TEMP CACHE CONTENT"] \
             << ["project/.kompoignore", "*.log\ntmp/"]
      project_dir = File.join(tmpdir, "project")

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint)

      path = Kompo::MakeFsC.path(args: {project_dir: project_dir})
      path_list = decode_embedded_paths(File.read(path))
      refute path_list.any? { |p| p.include?("debug.log") }
      refute path_list.any? { |p| p.include?("cache.txt") }
      assert path_list.any? { |p| p.include?("main.rb") }
    end
  end

  def test_make_fs_c_skips_symlinks_escaping_base_directory
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      tmpdir << ["work/lib/app.rb", "class App; end"] \
             << ["outside/secret.rb", "SECRET_DATA"]
      lib_dir = File.join(work_dir, "lib")
      outside_dir = File.join(tmpdir, "outside")

      # Create a symlink in lib_dir pointing to outside_dir
      symlink_path = File.join(lib_dir, "external_link")
      File.symlink(outside_dir, symlink_path)

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint, additional_paths: [lib_dir])

      path = Kompo::MakeFsC.path

      # Verify fs.c was generated
      assert File.exist?(path)
      content = File.read(path)

      # The symlink target content should NOT be included
      refute_includes content, "SECRET_DATA"

      # Regular file should still be included
      path_list = decode_embedded_paths(content)
      assert path_list.any? { |p| p.include?("app.rb") }
    end
  end

  def test_make_fs_c_allows_symlinks_within_base_directory
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      tmpdir << ["work/lib/real/internal.rb", "INTERNAL_CONTENT"]
      lib_dir = File.join(work_dir, "lib")
      real_dir = File.join(lib_dir, "real")

      # Create a symlink within the same base directory
      symlink_path = File.join(lib_dir, "linked.rb")
      File.symlink(File.join(real_dir, "internal.rb"), symlink_path)

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint, additional_paths: [lib_dir])

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
      content = File.read(path)

      # Internal symlink content should be included
      path_list = decode_embedded_paths(content)
      assert path_list.any? { |p| p.include?("internal.rb") }
    end
  end

  def test_make_fs_c_handles_binary_content_correctly
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      tmpdir << "work/lib/"
      lib_dir = File.join(work_dir, "lib")

      # Create a file with binary content (non-UTF8 bytes)
      binary_content = "\x00\x01\x02\xFF\xFE\xFD"
      binary_file = File.join(lib_dir, "binary.dat.rb") # Use .rb extension to not be skipped
      File.binwrite(binary_file, binary_content)

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint, additional_paths: [lib_dir])

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
      content = File.read(path)

      # The binary bytes should be embedded in FILES array
      # Binary content: \x00\x01\x02\xFF\xFE\xFD = 0, 1, 2, 255, 254, 253
      assert_includes content, "0,1,2,255,254,253"
    end
  end

  def test_make_fs_c_skips_duplicate_files
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)

      # Entrypoint is already added via CopyProjectFiles.entrypoint_path
      # Also add it via additional_paths to simulate "kompo . -e entry.rb" case
      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint, additional_paths: [entrypoint])

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
      content = File.read(path)

      # The entrypoint should only appear once, not twice
      path_list = decode_embedded_paths(content)
      entrypoint_count = path_list.count { |p| p == entrypoint }
      assert_equal 1, entrypoint_count, "Entrypoint should only be embedded once"
    end
  end

  def test_make_fs_c_skips_duplicate_files_in_directory
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      tmpdir << ["work/lib/app.rb", "class App; end"]
      lib_dir = File.join(work_dir, "lib")

      # Add the same directory twice to simulate duplicate
      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint, additional_paths: [lib_dir, lib_dir])

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
      content = File.read(path)

      # app.rb should only appear once
      path_list = decode_embedded_paths(content)
      app_count = path_list.count { |p| p.end_with?("app.rb") }
      assert_equal 1, app_count, "app.rb should only be embedded once"
    end
  end

  def test_make_fs_c_without_compress_generates_uncompressed
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint)
      path = Kompo::MakeFsC.path(args: {compress: false})

      assert File.exist?(path)
      content = File.read(path)

      # Should have COMPRESSION_ENABLED = 0
      assert_includes content, "const int COMPRESSION_ENABLED = 0"
      # Should have uncompressed FILES array with actual data
      assert_match(/const char FILES\[\] = \{\d/, content)
      # Should have dummy COMPRESSED_FILES
      assert_includes content, "const char COMPRESSED_FILES[] = {0}"
    end
  end

  def test_make_fs_c_with_compress_generates_compressed
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint)

      path = Kompo::MakeFsC.path(args: {compress: true})

      assert File.exist?(path)
      content = File.read(path)

      # Should have COMPRESSION_ENABLED = 1
      assert_includes content, "const int COMPRESSION_ENABLED = 1"
      # Should have COMPRESSED_FILES array with actual data
      assert_match(/const char COMPRESSED_FILES\[\] = \{\d/, content)
      # Should have FILES_BUFFER with size (no static for external linkage)
      assert_match(/^char FILES_BUFFER\[\d+\]/, content)
      # Should have dummy FILES
      assert_includes content, "const char FILES[] = {0}"
    end
  end

  def test_make_fs_c_compressed_data_is_smaller
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      # Create a file with repetitive content that compresses well
      tmpdir << ["work/lib/large.rb", "puts 'hello world'\n" * 100]
      lib_dir = File.join(work_dir, "lib")

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint, additional_paths: [lib_dir])

      path = Kompo::MakeFsC.path(args: {compress: true})

      assert File.exist?(path)
      content = File.read(path)

      # Extract COMPRESSED_FILES size and FILES_BUFFER_SIZE
      compressed_match = content.match(/const int COMPRESSED_FILES_SIZE = (\d+)/)
      original_match = content.match(/const int FILES_BUFFER_SIZE = (\d+)/)

      assert compressed_match, "Should have COMPRESSED_FILES_SIZE"
      assert original_match, "Should have FILES_BUFFER_SIZE"

      compressed_size = compressed_match[1].to_i
      original_size = original_match[1].to_i

      # Compressed size should be smaller than original
      assert compressed_size < original_size,
        "Compressed size (#{compressed_size}) should be smaller than original (#{original_size})"
    end
  end

  def test_make_fs_c_compressed_can_be_decompressed
    require "zlib"

    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir, content: "TEST_CONTENT_FOR_DECOMPRESSION")
      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint)

      path = Kompo::MakeFsC.path(args: {compress: true})
      content = File.read(path)

      # Extract COMPRESSED_FILES data
      compressed_match = content.match(/const char COMPRESSED_FILES\[\] = \{([^}]+)\}/)
      assert compressed_match, "Should have COMPRESSED_FILES array"

      # Convert the byte array back to binary data
      compressed_bytes = compressed_match[1].split(",").map(&:to_i).pack("C*")

      # Decompress using Zlib
      decompressed = Zlib.inflate(compressed_bytes)

      # The decompressed data should contain our test content
      assert_includes decompressed, "TEST_CONTENT_FOR_DECOMPRESSION"
    end
  end

  def test_make_fs_c_does_not_skip_binary_extensions_for_project_paths
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      tmpdir << ["work/app/assets/logo.png", "PNG_IMAGE_DATA"] \
             << ["work/app/assets/photo.jpg", "JPG_IMAGE_DATA"] \
             << ["work/app/assets/icon.svg", "SVG_DATA"]

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint,
        additional_paths: [File.join(work_dir, "app")])

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
      content = File.read(path)

      # Project paths should include image files (SKIP_EXTENSIONS not applied)
      path_list = decode_embedded_paths(content)
      assert path_list.any? { |p| p.include?("logo.png") }
      assert path_list.any? { |p| p.include?("photo.jpg") }
      assert path_list.any? { |p| p.include?("icon.svg") }
    end
  end

  def test_make_fs_c_skips_binary_extensions_for_gem_paths
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      gem_prefix = "work/bundle/ruby/3.4.0/gems/nokogiri-1.0"
      tmpdir << ["#{gem_prefix}/lib.rb", "module Nokogiri; end"] \
             << ["#{gem_prefix}/nokogiri.so", "BINARY_SO_DATA"] \
             << ["#{gem_prefix}/image.png", "GEM_PNG_DATA"] \
             << ["work/.bundle/config", "BUNDLE_PATH: bundle"] \
             << ["work/Gemfile", "source 'https://rubygems.org'"] \
             << ["work/Gemfile.lock", "GEM\n  specs:\n"]

      gem_dir = File.join(work_dir, "bundle", "ruby", "3.4.0", "gems", "nokogiri-1.0")
      bundle_config_dir = File.join(work_dir, ".bundle")

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint,
        gemfile_exists: true,
        bundler_config_path: File.join(bundle_config_dir, "config"),
        bundle_ruby_dir: gem_dir)

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
      content = File.read(path)

      # Gem paths should still skip .so and .png files
      path_list = decode_embedded_paths(content)
      refute path_list.any? { |p| p.include?("nokogiri.so") }
      refute path_list.any? { |p| p.include?("image.png") }
      assert path_list.any? { |p| p.include?("lib.rb") }
    end
  end

  def test_make_fs_c_skips_binary_extensions_for_stdlib_paths
    with_tmpdir do |tmpdir|
      work_dir, entrypoint = setup_work_dir_with_entrypoint(tmpdir)
      tmpdir << ["ruby_install/lib/ruby/3.4.0/json.rb", "module JSON; end"] \
             << ["ruby_install/lib/ruby/3.4.0/json.so", "BINARY_SO_DATA"]
      stdlib_dir = File.join(tmpdir, "ruby_install", "lib", "ruby", "3.4.0")

      mock_fs_c_dependencies(work_dir, tmpdir, entrypoint, stdlib_paths: [stdlib_dir])

      path = Kompo::MakeFsC.path

      assert File.exist?(path)
      content = File.read(path)

      path_list = decode_embedded_paths(content)
      refute path_list.any? { |p| p.include?("json.so") }
      assert path_list.any? { |p| p.include?("json.rb") }
    end
  end

  private

  def setup_work_dir_with_entrypoint(tmpdir, content: "puts 'hello'")
    tmpdir << ["work/main.rb", content]
    work_dir = File.join(tmpdir, "work")
    entrypoint = File.join(work_dir, "main.rb")
    [work_dir, entrypoint]
  end

  # Decode the PATHS array from generated fs.c content into a list of embedded path strings
  def decode_embedded_paths(fs_c_content)
    paths_match = fs_c_content.match(/const char PATHS\[\] = \{([^}]+)\}/)
    assert paths_match, "Should have PATHS array"
    paths_match[1].split(",").map(&:to_i).pack("C*").split("\0")
  end

  def mock_fs_c_dependencies(work_dir, tmpdir, entrypoint,
    additional_paths: [],
    gemfile_exists: false,
    gemspec_paths: [],
    bundler_config_path: nil,
    bundle_ruby_dir: nil,
    stdlib_paths: [])
    mock_task(Kompo::WorkDir, path: work_dir, original_dir: tmpdir)
    mock_task(Kompo::InstallRuby,
      ruby_install_dir: "/path/to/install",
      original_ruby_install_dir: "/path/to/install",
      ruby_major_minor: "3.4")
    mock_task(Kompo::CopyProjectFiles, entrypoint_path: entrypoint, additional_paths: additional_paths)
    mock_task(Kompo::CopyGemfile, gemfile_exists: gemfile_exists, gemspec_paths: gemspec_paths)
    mock_task(Kompo::BundleInstall, bundler_config_path: bundler_config_path, bundle_ruby_dir: bundle_ruby_dir)
    mock_task(Kompo::CheckStdlibs, paths: stdlib_paths)
  end
end
