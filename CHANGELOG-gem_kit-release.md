# Changelog

All notable changes to **gem_kit-release** are documented in this file. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The runtime gem it enforces has its own history in
[CHANGELOG-gem_kit.md](CHANGELOG-gem_kit.md): two gems, two schedules, two
files.

## [Unreleased]

## [0.1.0] - 2026-08-20

### Added

- `gem kit` — one RubyGems command, with subcommands `setup`, `bump`,
  `changelog`, `deprecations`, `release` and `tag`. Installing the gem is the
  whole installation; there is no Rakefile to edit and no binstub to add.
- `gem kit bump` refuses to move onto a deprecation's removal version while the
  old name is still in the tree, and `gem kit release` refuses to ship a
  version with an unkept promise or no changelog entry of its own.
- `GemKit::Release::Project` reads the gem's identity out of its `.gemspec`, so
  the normal case needs no configuration. In a repository holding several
  gemspecs it refuses to guess, and every command takes `--gem`.
- One changelog, one release document and one tag namespace per gem when a
  repository holds more than one gemspec: `CHANGELOG-<gem>.md`,
  `RELEASE-<gem>.md` and `<gem>-v<version>`, against plain `CHANGELOG.md`,
  `RELEASE.md` and `v<version>` when it holds one. The changelog has to be
  per-gem or the release gate — which asks whether the version being cut is the
  topmost released section — can only ever pass for one of them.
  `DEPRECATIONS.md` stays one per repository, because one policy governs all of
  it.
- `gem kit setup` writes DEPRECATIONS.md and RELEASE.md into the project,
  rendered for its name and versions. It is a `Thor::Group` generator — the
  machinery behind `rails generate` — so it reports `create` / `identical` /
  `conflict` per file and takes `--force`, `--skip` and `--pretend`.
- `GemKit::Release.plugin`, the extension seam. Another gem adds commands to
  `gem kit` by reopening the Thor class through it; a command added that way is
  listed, takes `--gem`, and gets a help page like any other. See
  [gem_kit-plugin](https://github.com/n-at-han-k/gem_kit-plugin).
- The command line is [Thor](https://github.com/rails/thor), so `gem kit` lists
  the commands and `gem kit help <command>` prints one command's arguments and
  options.
