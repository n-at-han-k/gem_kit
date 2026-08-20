# Changelog

All notable changes to **gem_kit** are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The release toolchain beside it has its own history in
[CHANGELOG-gem_kit-release.md](CHANGELOG-gem_kit-release.md): two gems, two
schedules, two files.

## [Unreleased]

## [0.1.0] - 2026-08-20

### Added

- `GemKit::Deprecate`. A deprecation is a dated promise: it names its
  replacement and the version the old name stops existing in. `deprecate` for a
  method, `superseded_by` for a renamed or moved constant.
- Built on `Gem::Deprecate`, so the message format and
  `Gem::Deprecate.skip_during` work as they already do. Warnings name the
  caller rather than the machinery, and a class-method deprecation is recorded
  against the class rather than its singleton.
- A registry — `registry`, `pending(version)`, `upcoming(version)` — which is
  what makes a deadline checkable. Each entry carries `name`, `replacement`,
  `removed_in` and `declared_at`.
- No dependencies beyond RubyGems' own, deliberately: a library that deprecates
  a name should not thereby acquire a release toolchain.
