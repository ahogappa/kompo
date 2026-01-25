# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2025-01-26

### Added
- `--dry-run` option to show compile command without executing [#17](https://github.com/ahogappa/kompo/pull/17)
- `--no-gemfile` option to skip Gemfile processing [#13](https://github.com/ahogappa/kompo/pull/13)
- `.kompoignore` files support for ignoring specific files in VFS [#20](https://github.com/ahogappa/kompo/pull/20)
- Duplicate file detection in VFS embedding [#15](https://github.com/ahogappa/kompo/pull/15)
- standardrb lint check to CI [#14](https://github.com/ahogappa/kompo/pull/14)

### Changed
- Set default progress mode to simple [#16](https://github.com/ahogappa/kompo/pull/16)
- Bump kompo-vfs minimum version to 0.5.1 [#23](https://github.com/ahogappa/kompo/pull/23)
- Use Taski.message instead of puts for dry-run output [#21](https://github.com/ahogappa/kompo/pull/21)
- Remove redundant compile command label from dry-run output [#22](https://github.com/ahogappa/kompo/pull/22)
- Update README to match actual implementation

### Fixed
- Extract LIBS from Makefiles including bundled gems [#19](https://github.com/ahogappa/kompo/pull/19)
- Support bundled gems native extensions for Ruby 4.0+ [#12](https://github.com/ahogappa/kompo/pull/12)

## [0.3.2] - 2025-01-25

### Fixed
- Embed gemspec files in VFS for runtime Bundler support [#10](https://github.com/ahogappa/kompo/pull/10)

## [0.3.1] - 2025-01-25

### Fixed
- Copy gemspec files when Gemfile contains `gemspec` directive [#8](https://github.com/ahogappa/kompo/pull/8)
- Fix "." directory handling to copy contents directly instead of creating nested structure [#8](https://github.com/ahogappa/kompo/pull/8)

## [0.3.0] - 2026-01-24

### Changed
- Use RTLD_NEXT for single binary creation process [#6](https://github.com/ahogappa/kompo/pull/6)
- Rewrite kompo with Taski-based parallel task system [#6](https://github.com/ahogappa/kompo/pull/6)
- Use ruby-build for Ruby installation [#5](https://github.com/ahogappa/kompo/pull/5)

### Added
- Ability to configure options for Ruby build

### Fixed
- Fix error messages
