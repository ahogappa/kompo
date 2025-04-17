# frozen_string_literal: true

require "tmpdir"
require "pathname"
require "optparse"
require "fileutils"
require "erb"
require "find"
require "async"
require_relative "kompo/version"

module Kompo
  class Context < Hash
    def initialize
      super
      self[:resolved] = {}
    end

    def method_missing(name, *args, &block)
      name = name.to_sym
      if key?(name)
        self[name]
      elsif name.match?(/([\w\d_-]+)=\z/)
        key = name.to_s.delete_suffix("=").to_sym
        self[key] = args.first
      else
        nil
      end
    end

    def respond_to_missing?(name, include_private = false)
      key?(name) || super
    end

    def resolved(klass)
      self[:resolved][klass] = true
    end

    def unresolved(klass)
      self[:resolved][klass] = false
    end
  end

  SETUP = %w[
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
  ]

  class Option
    attr_reader :option, :context

    def initialize
      @option = OptionParser.new
      @context = Context.new
    end

    def self.default
      opt = new
      opt.option.on("-e VAL", "--entrypoint=VAL", "File path to use for entry point. (default: './main.rb')") { |v| opt.context.entrypoint = v }
      # opt.option.on("-o VAL", "--output=VAL", "Name of the generated file. (default: current dir name)") { |v| opt.context.output = v }
      opt.option.on("-g VAL", "--use-group=VAL", "Group name to use with 'bundle install'. (default: 'default')") { |v| opt.context.use_group = v }
      opt.option.on("--[no-]gemfile", "Use gem in Gemfile. (default: automatically true if Gemfile is present)") { |v| opt.context.gemfile = v }
      opt.option.on("--local-kompo-fs-dir=VAL", "") { |v| opt.context.local_kompo_fs = v }
      opt.option.on("--verbose", "Verbose mode.") { |v| opt.context.verbose = v }
      # opt.option.on("--ignore-stdlib=VAL", Array, "Specify stdlibs not to include, separated by commas.") { |v| opt.context.ignore_stdlib = v }
      # opt.option.on("--dyn-link-lib=VAL", Array, "Specify libraries to be dynamic link, separated by commas.") { |v| opt.context.dyn_link_lib = v }
      opt.option.on("--dest-dir=VAL", "Output directry path. (default: current dir)") { |v| opt.context.dest_dir = v }
      # opt.option.on("--ruby-src-path=VAL", "Your Ruby source directry. Must be compiled with '--with-static-linked-ext'.") { |v| opt.context.ruby_src_path = v }
      opt.option.on("--bundle-cache=VAL", "Specify the directory created by 'bundle install --standalone'.") { |v| opt.context.bundle_cache = v }
      opt.option.on("--ruby-version=VAL", "Specify Ruby version. (default: current Ruby version)") { |v| opt.context.ruby_version = v }

      opt.option.on("--rebuild") { |v| opt.context.rebuild = v }
      opt.option.on("--repack") { |v| opt.context.repack = v }

      opt
    end

    def to_context
      @option.parse!(ARGV)
      @context.args = ARGV

      @context.repack = @context.repack || !@context.rebuild
      @context.rebuild = !@context.repack
      @context
    end
  end

  class Task
    def self.exec(context)
      return if context[:resolved].fetch(self) { false }

      task = new(context)
      resolve_build_dependences(task)
      task.definitions
      task.exec
      task.context.resolved(self)
    end

    def self.resolve_build_dependences(task)
      task.dependencies.each do |klass|
        klass.exec(task.context)
      end
    end

    def self.clean(context)
      return unless context[:resolved].fetch(self) { false }

      task = new(context)
      task.definitions
      task.clean
      resolve_clean_dependences(task)
      task.context.unresolved(self)
    end

    def self.resolve_clean_dependences(task)
      task.dependencies.reverse.each do |klass|
        klass.clean(task.context)
      end
    end

    def self.|(task)
      UnionTask.new(self, task)
    end

    def self.&(task)
      IntersectionTask.new(self, task)
    end

    attr_reader :context

    def initialize(context = Context.new)
      @context = context
    end

    def dependencies
      raise NotImplementedError
    end

    def definitions
    end

    def exec
    end

    def clean
    end

    def exec_command(command, info = nil, ret = false)
      puts "exec: #{info}" if info
      puts command
      if ret
        ret = `#{command}`.chomp
        if $?.exited?
          ret
        else
          raise "Failed to execute command: #{command}"
        end
      else
        system command, exception: true
      end
    end

    class UnionTask
      def initialize(left, right)
        @left = left
        @right = right
      end

      def self.exec(context)
        @left.exec(context)
        @right.exec(context)
      end
    end
  end

  class CheckHomebrew < Task
    def dependencies
      []
    end

    def exec
      context.use_homebrew = if system("which brew > /dev/null 2>&1")
        true
      else
        # TODO: return nil
        false
      end
    end
  end

  class InstallRubyBuild < Task
    #: () -> [Kompo::Task]
    def dependencies
      [
        MakeWorkDir,
        CheckHomebrew
      ]
    end

    def exec
      if system("which ruby-build > /dev/null 2>&1")
        puts "info: ruby-build already installed. version: #{`ruby-build --version`}"

        context.ruby_build = `which ruby-build`.chomp
      elsif system("which brew > /dev/null 2>&1")
        exec_command "brew install ruby-build", "Installing ruby-build via Homebrew"

        context.ruby_build = `brew --prefix ruby-build`.chomp
      else
        context.ruby_build = File.join(context.kompo_cache, "ruby-build", "bin", "ruby-build").chomp
        return if File.exist?(File.join(context.kompo_cache, "ruby-build"))

        exec_command "git clone https://github.com/rbenv/ruby-build.git #{File.join(context.kompo_cache, "ruby-build")}", "Cloning ruby-build repository"
      end
    end
  end

  class CheckRubyVersion < Task
    def dependencies
      []
    end

    def exec
      unless context.ruby_version
        ruby_version = "v#{RUBY_VERSION.tr(".", "_")}"
        puts "info: current ruby version: #{ruby_version}"

        context.ruby_version = ruby_version
      end
    end
  end

  class MakeWorkDir < Task
    def dependencies
      []
    end

    def definitions
      context.project_dir = Dir.pwd
      context.work_dir = Dir.mktmpdir(".kompo_work_dir")
      context.project_src_dir = File.join(context.work_dir, SecureRandom.uuid)
      context.dest_dir = context.dest_dir || context.project_dir
      context.kompo_cache = File.expand_path(File.join("~/.kompo/cache", File.basename(context.project_dir)))
      context.project_cache = File.expand_path(File.join("~/.kompo/cache", File.basename(context.project_dir)))
      context.local_ruby = `which ruby`.chomp
      context.local_bundler = `which bundler`.chomp
    end

    def exec
      # Create destination directory
      FileUtils.mkdir_p(context.dest_dir)
    end

    def clean
      # Remove work directory
      FileUtils.rm_rf(context.work_dir) if context.work_dir && Dir.exist?(context.work_dir)
    end
  end

  class InstallHomebrew < Task
    def dependencies
      [
        CheckHomebrew
      ]
    end

    def exec
      if context.use_homebrew == true
        puts "info: Homebrew already installed."
      elsif context.use_homebrew == false
        puts "info: Homebrew is not used. Skipping installation."
      else
        exec_command "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"", "Installing Homebrew"
      end
    end
  end

  class InstallCargo < Task
    def dependencies
      []
    end

    def definitions
      if system("which cargo > /dev/null 2>&1")
        context.cargo = `which cargo`.chomp
      else
        context.cargo = `which $HOME/.cargo/bin/cargo`.chomp
      end
    end

    def exec
      if system("which cargo > /dev/null 2>&1") || system("which $HOME/.cargo/bin/cargo > /dev/null 2>&1")
        puts "info: Cargo already installed. version: #{`#{context.cargo} --version`}"
      else
        exec_command "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh", "Installing Cargo"
      end
    end
  end

  class CpGemfile < Task
    def dependencies
      [
        MakeWorkDir
      ]
    end

    def definitions
      context.gemfile = context.gemfile || File.exist?(File.join(context.project_dir, "Gemfile"))
    end

    def exec
      if context.gemfile
        if File.exist?(File.join(context.project_dir, "Gemfile"))
          FileUtils.cp(File.join(context.project_dir, "Gemfile"), context.work_dir)
        end
        if File.exist?(File.join(context.project_dir, "Gemfile.lock"))
          FileUtils.cp(File.join(context.project_dir, "Gemfile.lock"), context.work_dir)
        end
      end
    end

    def clean
      if context.gemfile
        FileUtils.rm_rf(File.join(context.work_dir, "Gemfile")) if File.exist?(File.join(context.work_dir, "Gemfile"))
        FileUtils.rm_rf(File.join(context.work_dir, "Gemfile.lock")) if File.exist?(File.join(context.work_dir, "Gemfile.lock"))
      end
    end
  end

  class CpProjectDir < Task
    def dependencies
      [
        MakeWorkDir,
      ]
    end

    def definitions
      context.entrypoint = context.entrypoint || File.join(context.project_dir, "main.rb")
      context.work_dir_entrypoint = File.join(context.work_dir, File.basename(context.entrypoint))
    end

    def exec
      context.args.each do |arg|
        FileUtils.cp_r(File.join(context.project_dir, arg), context.work_dir) if File.exist?(File.join(context.project_dir, arg))
      end
      FileUtils.cp_r(context.entrypoint, context.work_dir_entrypoint)
    end

    def clean
      context.args.each do |arg|
        FileUtils.rm_rf(File.join(context.work_dir, arg)) if File.exist?(File.join(context.work_dir, arg))
      end
      FileUtils.rm_rf(context.work_dir_entrypoint) if File.exist?(context.entrypoint)
    end
  end

  class CdWorkingDir < Task
    def dependencies
      [
        CpGemfile,
        CpProjectDir
      ]
    end

    def exec
      if context.verbose
        puts "info: Changing working directory to #{context.work_dir}"
      end
      Dir.chdir(context.work_dir)
    end
  end

  class InstallRuby < Task
    def dependencies
      [
        InstallRubyBuild,
        CheckRubyVersion
      ]
    end

    def definitions
      context.ruby_cache = File.join(context.kompo_cache, "ruby", context.ruby_version)
      context.ruby_major_and_minor = ruby_major_and_minor
      context.ruby_pc = "ruby.pc"
      context.ruby_static_a = File.join(context.work_dir, "lib", "libruby-static.a")
      context.ruby = File.join(context.work_dir, "bin", "ruby")
      context.bundler = File.join(context.work_dir, "bin", "bundler")
      context.ruby_build_build_path = File.join(context.work_dir, "build")
    end

    def exec
      if false # context.repack && File.exist?(File.join(context.project_cache, "lib", "libruby-static.a"))
        puts "info: #{File.basename(context.ruby_static_a)} already exists. Skipping build."

        FileUtils.cp_r([
          File.join(context.project_cache, "bin"),
          File.join(context.project_cache, "lib"),
          File.join(context.project_cache, "include"),
          File.join(context.project_cache, "build"),
        ], context.work_dir)
        return
      end

      opts = [
        "--disable-install-doc",
        "--disable-install-rdoc",
        "--disable-install-capi",
        "--with-static-linked-ext",
        "--with-ruby-pc=#{context.ruby_pc}",
        "--with-ext=#{SETUP.join(",")}",
        '--with-setup=Setup',
        "--disable-shared"
      ].join(" ")

      # Build Ruby using ruby-build
      command = [
        "RUBY_CONFIGURE_OPTS='#{opts}'",
        "RUBY_BUILD_CACHE_PATH='#{context.kompo_cache}'",
        "TMPDIR=#{context.work_dir}",
        "RUBY_BUILD_BUILD_PATH=#{context.ruby_build_build_path}",
        context.ruby_build.to_s,
        "--verbose",
        "--keep",
        "--patch",
        context.ruby_version.delete_prefix("v").tr("_", "."),
        "<",
        "#{File.join(__dir__, "ext", "Setup.patch")}",
        context.work_dir.to_s
      ].join(" ")

      exec_command command, "Building Ruby with ruby-build"

      # FileUtils.cp_r([
      #   File.join(context.work_dir, "bin"),
      #   File.join(context.work_dir, "lib"),
      #   File.join(context.work_dir, "include"),
      #   context.ruby_build_build_path,
      # ], context.project_cache)
    end

    def clean
      if context.ruby_cache && Dir.exist?(context.ruby_cache)
        FileUtils.rm_rf(context.ruby_cache)
      end
    end

    def ruby_major_and_minor
      ruby_version = RUBY_VERSION.split(".")
      "#{ruby_version[0]}.#{ruby_version[1]}"
    end
  end

  class InstallKompoFs < Task
    def dependencies
      [
        MakeWorkDir,
        InstallHomebrew,
        InstallCargo
      ]
    end

    def definitions
      if context.use_homebrew
        context.kompo_lib = File.join(`brew --prefix kompo-vfs`.chomp, 'lib')
      elsif context.local_kompo_fs
        context.kompo_lib = File.expand_path(File.join(context.local_kompo_fs, "target", "release"))
      else
        context.kompo_lib = File.join(context.kompo_cache, "kompo-vfs", "target", "release")
      end
    end

    def exec
      if context.use_homebrew
        exec_command "brew tap ahogappa/kompo-vfs https://github.com/ahogappa/kompo-vfs.git", "Installing kompo-vfs via Homebrew"
        exec_command "brew install kompo-vfs", "Installing kompo-vfs via Homebrew"
      elsif context.local_kompo_fs
        exec_command "#{context.cargo} build --release --manifest-path #{File.join(context.local_kompo_fs, "Cargo.toml")}", "Building local kompo-fs"
      else
        unless File.exist?(File.join(context.kompo_cache, "kompo-vfs"))
          exec_command "git clone https://github.com/ahogappa/kompo-vfs.git #{File.join(context.kompo_cache, "kompo-vfs")}", "Cloning kompo-vfs repository"
        end

        unless File.exist?(File.join(context.kompo_cache, "kompo-vfs", "target", "release"))
          exec_command "#{context.cargo} build --release --manifest-path #{File.join(context.kompo_cache, "kompo-vfs", "Cargo.toml")}", "Building kompo-vfs"
        end
      end
    end

    def clean
      if context.use_homebrew
        # TODO
      elsif context.local_kompo_fs
        exec_command "#{context.cargo} clean --manifest-path #{context.local_kompo_fs}/Cargo.toml", "Cleaning local kompo-fs"
      else
        exec_command "#{context.cargo} clean --manifest-path #{File.join(context.kompo_cache, "kompo-vfs", "Cargo.toml")}", "Cleaning kompo-fs"
      end
    end
  end

  class BundleInstall < Task
    def dependencies
      [
        CdWorkingDir,
        InstallRuby
      ]
    end

    def definitions
      if context.gemfile
        context.use_group = context.use_group || "default"
        context.bundle_cache = context.bundle_cache || File.join(context.kompo_cache, "bundle", context.ruby_version)
        context.bundle_bundler_setup = File.join(context.work_dir, "bundler", "setup.rb")
        context.bundle_ruby_version_dir = File.join(context.work_dir, "ruby", "#{context.ruby_major_and_minor}.0")
        context.work_dir_bundler = File.join(context.work_dir, "bundler", "setup.rb")
        context.work_dir_bundler_setup = File.join(context.work_dir, "bundler", "setup.rb")
      end
    end

    def exec
      if context.gemfile
        exec_command "#{context.bundler} config set path #{context.work_dir}", "Setting bundler path"
        exec_command "#{context.bundler} install --standalone=#{context.use_group}"
        # FileUtils.mkdir_p(context.work_dir_bundler)
        # FileUtils.cp_r(context.bundle_bundler_setup, context.work_dir_bundler_setup)
      end
    end

    def clean
      if context.gemfile
        FileUtils.rm_rf(context.bundle_cache) if context.bundle_cache && Dir.exist?(context.bundle_cache)
        FileUtils.rm_rf(context.bundle_ruby_version_dir) if context.bundle_ruby_version_dir && Dir.exist?(context.bundle_ruby_version_dir)
        FileUtils.rm_rf(context.bundle_bundler_setup) if context.bundle_bundler_setup && File.exist?(context.bundle_bundler_setup)
        FileUtils.rm_rf(context.project_bundler_setup) if context.project_bundler_setup && File.exist?(context.project_bundler_setup)
      end
    end
  end

  class BuildNativeGem < Task
    def dependencies
      [
        CpGemfile,
        InstallCargo,
        InstallRuby,
        BundleInstall
      ]
    end

    def exec
      context.exts = []
      context.exts_libs = []
      context.exts_dirs = []

      if context.gemfile
        context.exts_dirs = File.join(context.work_dir, 'exts')
        Dir.glob(File.join(context.bundle_ruby_version_dir, "gems/**/extconf.rb")).each do |makefile_dir|
          dir_name = File.dirname(makefile_dir)
          makefile = File.join(dir_name, "Makefile")
          if File.exist?(cargo_toml = File.join(dir_name, "Cargo.toml"))
            command = [
              "cargo",
              "rustc",
              "--release",
              "--crate-type=staticlib",
              "--target-dir",
              "target",
              "--manifest-path=#{cargo_toml}"
            ].join(" ")
            exec_command command, "cargo build"
            copy_targets = Dir.glob(File.join(dir_name, "target/release/*.a"))
          else
            copy_targets = []
            Dir.chdir(dir_name) { |path|
              command = [
                context.local_ruby,
                "extconf.rb"
              ].join(" ")

              exec_command(command, "ruby extconf.rb") unless File.exist?(File.join(context.exts_dirs, File.basename(dir_name)))

              objs = File.read("./Makefile").match(/OBJS = (.*\.o)/)[1]

              command = ["make", objs, "--always-make"].join(" ")

              exec_command(command, "make OBJS") unless File.exist?(File.join(context.exts_dirs, File.basename(dir_name)))

              context.exts_libs += File.read("./Makefile").match(/^libpath = (.*)/)[1].split(" ")

              copy_targets = objs.split(" ").map { File.join(dir_name, it) }
            }
          end

          dir = FileUtils.mkdir_p(File.join(context.work_dir, 'exts', File.basename(dir_name))).first
          FileUtils.cp(copy_targets, dir)
          prefix = File.read(makefile).scan(/target_prefix = (.*)/).join.delete_prefix("/")
          target_name = File.read(makefile).scan(/TARGET_NAME = (.*)/).join
          context.exts << [File.join(prefix, "#{target_name}.so").delete_prefix("/"), "Init_#{target_name}"]
        end
      end
    end
  end

  class MakeMainC < Task
    def dependencies
      [
        BundleInstall,
        BuildNativeGem
      ]
    end

    def definitions
      context.main_c = File.join(context.work_dir, "main.c")
    end

    def exec
      return if File.exist?(context.main_c)

      File.write(context.main_c, ERB.new(File.read(File.join(__dir__, "main.c.erb"))).result(binding))
    end

    def clean
      if context.main_c && File.exist?(context.main_c)
        FileUtils.rm_rf(context.main_c)
      end
    end
  end

  class CheckStdlibs < Task
    def dependencies
      [
        InstallRuby
      ]
    end

    def exec
      commands = [
        context.ruby.to_s,
        "-e",
        "'puts $:'"
      ].join(" ")

      context.ruby_std_libs = exec_command(commands, "Checking stdlibs", true).split("\n")
    end
  end

  class RequireBundlerSetup < Task
    def dependencies
      [
        InstallRuby,
        CheckStdlibs,
        BundleInstall
      ]
    end

    def exec
      if context.gemfile
        commands = [
          context.ruby.to_s,
          "-r",
          context.bundle_bundler_setup.to_s,
          "-e",
          "'puts $:'"
        ].join(" ")

        context.gems = exec_command(commands, "Requiring bundler setup", true).split("\n") - context.ruby_std_libs
      else
        context.gems = []
      end
    end
  end

  KompoFile = Struct.new(:path, :bytes)

  class MakeFsC < Task
    def dependencies
      [
        BundleInstall,
        RequireBundlerSetup
      ]
    end

    def definitions
       context.fs_c = File.join(context.work_dir, "fs.c")
    end

    def exec
      return if File.exist?(context.fs_c)

      context.embeds = context.args + context.gems + context.ruby_std_libs + [context.work_dir_entrypoint, context.work_dir_bundler_setup].compact

      @files = []
      @file_bytes = []
      @paths = []
      @file_sizes = [0]

      Async do
        context.embeds.each do |arg_path|
          expand_path = File.expand_path(arg_path)
          if File.directory?(expand_path)
            Async do
              Find.find(expand_path) do |path|
                Find.prune if path.end_with?(".git", "/ports", "/logs", "/spec", ".github", "/docs", "/exe")
                next if path.end_with?(".so", ".c", ".h", ".o", ".java", ".jar", ".gz", ".dat", ".sqlite3", ".exe")
                next if path.end_with?(".gem", ".out", ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".ico", ".svg", ".webp", ".ttf", ".data")
                next if path.end_with?("selenium-manager")
                next if File.directory?(path)

                add_file_bytes(build_file_from_path(path))
              end
            end
          else
            add_file_bytes(build_file_from_path(expand_path))
          end
        end
      end.wait

      File.write(context.fs_c, ERB.new(File.read(File.join(__dir__, "fs.c.erb"))).result(binding))
    end

    def clean
      if context.fs_c && File.exist?(context.fs_c)
        FileUtils.rm_rf(context.fs_c)
      end
    end

    def build_file_from_path(path)
      bytes = Async do
        File.read(path).bytes
      end.wait

      puts path
      path = (path.bytes << 0)

      KompoFile.new(path, bytes)
    end

    def add_file_bytes(file)
      @file_bytes.concat(file.bytes)
      @paths.concat(file.path)
      prev_size = @file_sizes.last
      @file_sizes << (prev_size + file.bytes.size)
    end
  end

  class Packing < Task
    def dependencies
      [
        InstallKompoFs,
        MakeMainC,
        MakeFsC
      ]
    end

    def definitions
      context.ruby_lib = File.join(context.work_dir, "lib")
    end

    def exec
      commands = [
        'gcc',
        '-O3',
        get_ruby_header,
        ldflags,
        "-L#{context.ruby_lib}",
        "-L#{context.kompo_lib}",
        "-fstack-protector-strong",
        "-rdynamic -Wl,-export-dynamic",
        context.main_c,
        context.fs_c,
        "-Wl,-Bstatic",
        Dir.glob(File.join(context.ruby_build_build_path, 'ruby-*', 'ext', '**', '*.o')).join(' '),
        Dir.glob("#{context.exts_dirs}/**/*.o").join(' '),
        '-lruby-static',
        get_libs,
        '-o', File.join(context.dest_dir, File.basename(context.project_dir)),
      ].join(' ')

      exec_command commands, "Packing"
    end

    def clean
      if File.exist?(File.join(context.dest_dir, File.basename(context.project_dir)))
        FileUtils.rm_rf(File.join(context.dest_dir, File.basename(context.project_dir)))
      end
    end

    def get_from_ruby_pc(option)
      command = [
        "pkg-config",
        "#{option}",
        "#{File.join(context.work_dir, "lib", "pkgconfig", context.ruby_pc)}",
      ].join(" ")

      exec_command(command, "pkg-config", true)
    end

    def get_ruby_header
      get_from_ruby_pc("--cflags")
    end

    def get_mainlibs
      get_from_ruby_pc("--variable=MAINLIBS")
    end

    def extract_gem_libs
      Dir.glob("#{context.bundle_cache}/ruby/*/gems/*/ext/*/Makefile")
        .flat_map {File.read(it).scan(/^LIBS = (.*)/)[0]}
        .compact
        .flat_map { it.split(" ") }
        .uniq
        .flat_map { it.start_with?("-l") ? it : "-l" + File.basename(it, ".a").delete_prefix("lib") }
        .join(" ")
    end

    def ldflags
      (Dir.glob("#{context.bundle_cache}/ruby/*/gems/*/ext/*/Makefile")
      .flat_map {File.read(it).scan(/^ldflags\s+= (.*)/)[0]}
      .compact
      .flat_map { it.split(" ") }
      .uniq
      .filter{_1.start_with?('-L') ? _1 : false} +
      Dir.glob("#{context.bundle_cache}/ruby/*/gems/*/ext/*/Makefile")
      .flat_map {File.read(it).scan(/^LDFLAGS\s+= (.*)/)[0]}
      .compact
      .flat_map { it.split(" ") }
      .uniq
      .filter{_1.start_with?('-L') ? _1 : false}
      ).join(" ")
    end

    def extlibs
      Dir.glob(File.join(context.ruby_build_build_path, 'ruby-*', 'ext', '**', 'exts.mk'))
      .flat_map{File.read(_1).scan(/^EXTLIBS\s+= (.*)/)[0]}
      .compact
      .flat_map { it.split(" ") }
      .uniq
      .join(" ")
    end

    def get_libs
      main_lib = get_mainlibs
      ruby_std_gem_libs = extlibs
      gem_libs = extract_gem_libs
      dyn_link_libs = (["pthread", "dl", "m", "c"]).map { "-l" + it }
      dyn, static = eval("%W[#{main_lib} #{gem_libs} #{ruby_std_gem_libs}]").filter{_1.start_with?(/-l\w/)}.uniq
        .partition { dyn_link_libs.include?(it) }
      dyn << '-lc'
      dyn.unshift "-Wl,-Bdynamic"
      # static.unshift "-Wl,-Bstatic"

      static.join(" ") + " " + "-lkompo_fs -lkompo_wrap" + " " + dyn.join(" ")
    end
  end
end
