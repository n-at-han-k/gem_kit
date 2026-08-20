# Changelog

All notable changes to **gem_kit-release** are documented in this file. The
format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The runtime gem it enforces has its own history in
[CHANGELOG-gem_kit.md](CHANGELOG-gem_kit.md): two gems, two schedules, two
files.

## [Unreleased]

## [0.3.0] - 2026-08-20

### Changed

- **`gem kit release` refuses while the working tree has uncommitted changes.**
  A gem built from an uncommitted tree is a gem whose source exists nowhere —
  and `bump` and `changelog --write` leave exactly two such files behind, which
  is precisely when someone reaches for `release`. `--allow-dirty` overrides
  it; a directory that is not a git repository is not affected.
- **`gem kit release` tags.** It was behind `--tag` and did not push; tagging
  is part of releasing, so it now runs by default and pushes the tag. It runs
  *after* the gem is pushed, so a tag never names a version that failed to
  publish. `--no-tag` skips it, and `gem kit tag` still exists for tagging on
  its own.

## [0.2.2] - 2026-08-20

### Fixed

- A gemspec that exists but does not parse crashed with a Thor backtrace
  instead of reporting itself. `Project.detect` succeeds on any gemspec that is
  there — the parse happens later, lazily, in whichever command first asks for
  the version — so rescuing in `Commands::Command#project` never caught it.
  `GemKit::Release.run` now rescues `Project::NotFound` and
  `Project::Ambiguous` too, which is the one place that covers every command.

## [0.2.1] - 2026-08-20

### Fixed

- 0.2.0 could not be loaded at all once installed. `lib/gem_kit/release.rb` and
  `lib/gem_kit/release/cli.rb` reached the gem_kit gem with `require_relative
  "../gem_kit"`, which resolves inside gem_kit-release's own directory — and
  there is no `lib/gem_kit.rb` there, because that file belongs to the other
  gem. It worked in the repository the two are developed in, where they share
  one `lib/`, and nowhere else. Both are plain `require "gem_kit"` now.

## [0.2.0] - 2026-08-20

### Changed

- **The command line is [Thor](https://github.com/rails/thor), not dry-cli.**
  `gem kit` still lists the commands; per-command help is now
  `gem kit help <command>` rather than `gem kit <command> --help`. The change
  was for `Thor::Group` and `Thor::Actions` — see `gem kit setup` below.
- `gem kit setup` is a generator rather than a pair of `File.write` calls. It
  reports `create` / `identical` / `conflict` per file, prompts before
  overwriting something that differs, and takes `--force`, `--skip`,
  `--pretend` and `--quiet` — all of it from Thor rather than hand-rolled.
- In a repository holding more than one gemspec, every command now takes
  `--gem` and refuses to guess without it. The changelog, the release document
  and the tag are per-gem there — `CHANGELOG-<gem>.md`, `RELEASE-<gem>.md` and
  `<gem>-v<version>` — against plain `CHANGELOG.md`, `RELEASE.md` and
  `v<version>` in a repository with one. The changelog has to be per-gem or the
  release gate, which asks whether the version being cut is the topmost
  released section, can only ever pass for one of them. `DEPRECATIONS.md` stays
  one per repository, because one policy governs all of it.

### Added

- `GemKit::Release.plugin`, the extension seam. Another gem adds commands to
  `gem kit` by reopening the Thor class through it; a command added that way is
  listed, takes `--gem`, and gets a help page like any other. See
  [gem_kit-plugin](https://github.com/n-at-han-k/gem_kit-plugin).
- `gem kit tag` takes `--prefix`, defaulting to the per-repository convention
  above.

### Removed

- **`GemKit::Release::Deprecate` — it is `GemKit::Deprecate`, in the `gem_kit`
  gem.** A deprecation is declared at runtime and enforced at release time, so
  keeping both halves in one gem meant a library that deprecates a name
  acquired a release toolchain to do it. `gem_kit` is now a dependency of this
  gem, so `GemKit::Deprecate` is present either way; the constant simply moved.

  Removed outright rather than deprecated, which is not what this gem tells you
  to do. 0.1.0 was published for a few hours and downloaded zero times, and a
  shim for a name nobody has is ceremony rather than care.

### Fixed

- `Project#next_major_version` returned `"5"` for a 4.x gem, which read badly
  everywhere it surfaced — `deprecate :old, "New", "5"`, "removed in 5". It is
  `"5.0"` now. `Gem::Version` treats the two as equal, so deadlines already
  declared either way still compare the same.

## [0.1.0] - 2026-08-20

### Added

- `gem kit` — one RubyGems command, with subcommands `setup`, `bump`,
  `changelog`, `deprecations`, `release` and `tag`, on dry-cli. Installing the
  gem is the whole installation; there is no Rakefile to edit and no binstub to
  add.
- `gem kit bump` refuses to move onto a deprecation's removal version while the
  old name is still in the tree, and `gem kit release` refuses to ship a
  version with an unkept promise or no changelog entry of its own.
- `GemKit::Release::Project` reads the gem's identity out of its `.gemspec`, so
  the normal case needs no configuration.
- `GemKit::Release::Changelog`, a parser and linter for CHANGELOG.md against
  Keep a Changelog, and `GemKit::Release::VersionFile`, the semver arithmetic
  and the version-file rewrite.
- `GemKit::Release::Deprecate`, the deprecation DSL — moved to the `gem_kit`
  gem in 0.2.0.
