# Changelog

All notable changes to **gem_kit** are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

0.1.0 and 0.1.1 were a different gem under this name — a template you cloned to
start a gem — and are not documented here. That template still exists, as
`template/` in this repository, but it is cloned rather than installed.

The release toolchain beside this gem has its own history in
[CHANGELOG-gem_kit-release.md](CHANGELOG-gem_kit-release.md): two gems, two
schedules, two files.

## [Unreleased]

## [0.2.0] - 2026-08-20

### Changed

- **gem_kit is no longer a gem template.** It is the runtime half of the kit:
  the DSL for declaring a deprecation. Installing it gets you
  `GemKit::Deprecate` and nothing else. If you were using the template, clone
  `template/` from the repository instead — `gem install gem_kit` was never how
  it was meant to be used.

### Added

- `GemKit::Deprecate`. A deprecation is a dated promise: it names its
  replacement and the version the old name stops existing in. `deprecate` for a
  method, `superseded_by` for a renamed or moved constant.
- Built on `Gem::Deprecate`, so the message format and
  `Gem::Deprecate.skip_during` work as they already do. Warnings name the
  caller rather than the machinery, and a class-method deprecation is recorded
  against the class rather than its singleton.
- A registry — `registry`, `pending(version)`, `upcoming(version)` — which is
  what makes a deadline checkable rather than merely stated. Each entry carries
  `name`, `replacement`, `removed_in` and `declared_at`.
- No dependencies beyond RubyGems' own, deliberately: a library that deprecates
  a name should not thereby acquire a release toolchain. The toolchain is
  `gem_kit-release`, which reads this registry.

### Removed

- Everything the template gem shipped: `bin/01-rename-gem`,
  `bin/02-choose-license`, `bin/03-update-spec`, `exe/gem_kit` and the rest.
  They are in `template/` in the repository.
