# Changelog

All notable changes to the gems in this repository are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Two gems live here and each carries its own version, so each entry names the
gem it belongs to.

## [Unreleased]

## [0.1.0] - 2026-08-20

### Added

- **gem_kit** — `GemKit::Deprecate`, the runtime half. A deprecation is a dated
  promise: it names its replacement and the version the old name stops existing
  in. `deprecate` for a method, `superseded_by` for a renamed or moved
  constant. Built on `Gem::Deprecate`, so the message format and
  `Gem::Deprecate.skip_during` work as they already do. Every declaration
  registers itself, which is what makes the deadline checkable. No dependencies
  beyond RubyGems' own — a library that deprecates a name should not thereby
  acquire a release toolchain.
- **gem_kit-release** — the maintainer's half, as one RubyGems command:
  `gem kit setup|bump|changelog|deprecations|release|tag`. The subcommands are
  [dry-cli](https://dry-rb.org/gems/dry-cli/) commands, so `gem kit` lists them
  and `gem kit <subcommand> --help` prints arguments, options and examples.
  `bump` refuses to move onto a deprecation's removal version while the old
  name is still in the tree; `release` refuses to ship a version with an unkept
  promise or no changelog entry of its own. Everything is read from the
  `.gemspec` in the working directory, so the normal case needs no
  configuration.
- **gem_kit-release** — `gem kit setup` writes DEPRECATIONS.md and RELEASE.md
  into the project it runs in, rendered for its name and versions. It is a
  `Thor::Group` generator, the machinery behind `rails generate`, so it reports
  `create` / `identical` / `conflict` per file and takes `--force`, `--skip`
  and `--pretend`.
- **gem_kit-release** — `GemKit::Release.plugin`, the extension seam. Another
  gem can add commands to `gem kit` by reopening the Thor class through it; a
  command added that way is listed, takes `--gem`, and gets a help page like
  any other. See gem_kit-plugin for a worked example.
- The gem template this repository used to be now lives under `template/`.
