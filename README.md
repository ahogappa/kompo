# Kompo
A tool to pack Ruby and Ruby scripts in one binary. This tool is still under development.

## Concept

Kompo makes it dead simple to distribute Ruby applications. Just run one command, and you get a single binary that works anywhere—no Ruby installation required.

```sh
$ kompo
$ ./main  # That's it!
```

### Why Kompo?

- **Dead Simple**: One command to build, one file to distribute. No complex configuration, no build scripts, no Docker containers.

- **Zero Dependencies for Users**: Your users just download and run. No Ruby, no gems, no environment setup—it just works.

- **Full CRuby Compatibility**: Unlike mruby-based solutions, Kompo embeds the official CRuby interpreter. Your existing code, gems, and C extensions work without modification.

- **Cross-Platform**: Build binaries for macOS and Linux. (Windows support is planned)

- **Batteries Included**: All your gems, including native extensions, are bundled automatically.

### How It Works

Kompo uses a Virtual File System (VFS) to embed Ruby source code, gems, and the Ruby interpreter into a single binary. At runtime, the embedded VFS provides transparent access to these files, allowing Ruby to operate as if everything were installed normally on the filesystem.

## Installation
```sh
$ gem install kompo
```

## Usage

### prerequisites
Install [kompo-vfs](https://github.com/ahogappa/kompo-vfs).

#### Homebrew
```sh
$ brew tap ahogappa/kompo-vfs https://github.com/ahogappa/kompo-vfs.git
$ brew install ahogappa/kompo-vfs/kompo-vfs
```

### Building
To build komp-vfs, you need to have cargo installation.
```sh
$ git clone https://github.com/ahogappa/kompo-vfs.git
$ cd kompo-vfs
$ cargo build --release
```

## Options

```
Usage: kompo [options] [files...]

Options:
    -e, --entrypoint=FILE        Entry point file (default: main.rb)
    -o, --output=DIR             Output directory for the binary
        --ruby-version=VERSION   Ruby version to use (default: current Ruby version)
        --ruby-source=PATH       Path to Ruby source tarball or directory
        --no-cache               Build Ruby from source, ignoring cache
        --no-stdlib              Exclude Ruby standard library from binary
        --no-gemfile             Skip Gemfile processing (no bundle install)
        --local-vfs-path=PATH    Path to local kompo-vfs for development
        --clean[=VERSION]        Clean cache (current version by default, or specify VERSION, or "all")
        --dry-run                Show final compile command without executing it
    -t, --tree                   Show task dependency tree and exit
    -v, --version                Show version
    -h, --help                   Show this help message

Files:
    Additional files and directories to include in the binary
```

### Option Details

| Option | Description |
|--------|-------------|
| `-e, --entrypoint` | Specifies the main Ruby file to execute. Defaults to `main.rb`. |
| `-o, --output` | Directory where the final binary will be placed. Defaults to current directory. |
| `--ruby-version` | Ruby version to embed. Kompo will build and cache this version. |
| `--ruby-source` | Use a local Ruby source instead of downloading. Useful for custom Ruby builds. |
| `--no-cache` | Force a fresh Ruby build, ignoring any cached version. |
| `--no-stdlib` | Reduce binary size by excluding Ruby standard library. Only use if your app doesn't need stdlib. |
| `--no-gemfile` | Skip Gemfile processing and bundle install. Useful when your project doesn't use Bundler. |
| `--local-vfs-path` | Use a local kompo-vfs build instead of Homebrew installation. Useful for development. |
| `--clean` | Remove cached Ruby builds. Use `--clean=all` to remove all versions. |
| `--dry-run` | Show the final compile command without executing it. Useful for debugging build issues. |
| `-t, --tree` | Display the task dependency graph and exit without building. |
| `-v, --version` | Display the kompo version and exit. |

### Examples

```sh
# Basic usage - pack main.rb and lib/ directory
$ kompo main.rb lib/

# Specify entry point and output directory
$ kompo -e app.rb -o ./dist src/ config/

# Use a specific Ruby version
$ kompo --ruby-version=3.3.0 main.rb

# Development: use local kompo-vfs
$ kompo --local-vfs-path=/path/to/kompo-vfs main.rb

# Clean all cached Ruby builds
$ kompo --clean=all
```

## .kompoignore

You can create a `.kompoignore` file in your project root to exclude files from the binary. This file follows the same syntax as `.gitignore`.

### Syntax

```gitignore
# Comments start with #
*.log           # Ignore all .log files
tmp/            # Ignore tmp directory
**/cache/       # Ignore cache directories at any depth
!important.log  # Negate pattern (don't ignore important.log)
spec/           # Ignore spec directory
test/           # Ignore test directory
node_modules/   # Ignore node_modules
```

### Supported Patterns

| Pattern | Description |
|---------|-------------|
| `*.log` | Glob pattern - matches all .log files |
| `tmp/` | Directory pattern - matches tmp directory and contents |
| `**/cache/` | Double star - matches cache at any depth |
| `!file` | Negation - excludes file from ignore list |
| `/config.yml` | Anchored - matches only at root level |

### Notes

- `.kompoignore` only affects project files, not Ruby standard library or gems
- Patterns are matched against paths relative to the project root
- Comments and empty lines are ignored

## Samples

Sample applications demonstrating various use cases are available in the [samples](./samples) directory:

* [hello](./samples/hello)
  * Simple hello world script.
* [native_gems](./samples/native_gems)
  * Demonstrates native extension gems (nokogiri, sqlite3, and msgpack).
* [sinatra_and_sqlite](./samples/sinatra_and_sqlite)
  * Simple Sinatra app with SQLite3.
* [rails](./samples/rails/sample)
  * Simple Rails application.

## Development

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ahogappa/kompo.
