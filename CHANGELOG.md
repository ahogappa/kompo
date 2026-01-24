# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
