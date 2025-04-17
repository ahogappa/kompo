# Kompo
A tool to pack Ruby and Ruby scripts in one binary. This tool is still under development.

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

## examples

* hello
  * simple hello world script.
* sinatra_and_sqlite
  * 🚧
* rails
  * 🚧

## Development

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ahogappa/kompo.
