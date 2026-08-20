# gem_kit

Two gems, split along the line that matters: **what a library needs while it is
running**, and **what its maintainer needs while releasing it**.

| Gem | Half | Depends on |
| --- | --- | --- |
| [`gem_kit`](gem_kit.gemspec) | `GemKit::Deprecate` — declare a deprecation | nothing beyond RubyGems |
| [`gem_kit-release`](gem_kit-release.gemspec) | `gem kit …` — enforce it at release time | `gem_kit`, `thor` |

A deprecation is a **dated promise**: it names its replacement *and* the version
the old name stops existing in. The promise is declared at runtime and enforced
at release time — which is exactly why these are two gems. A library that
deprecates a name should not thereby acquire a release toolchain, and only the
enforcing end needs one installed.

```ruby
# Gemfile
gem "gem_kit"                              # runtime: declaring
gem "gem_kit-release", group: :development # release:  enforcing
```

## Declaring — gem_kit

A method:

```ruby
class Session
  extend GemKit::Deprecate

  def old_reset = new_reset
  deprecate :old_reset, "Session#new_reset", "5.0"
end
```

A renamed or moved constant — leave the old name as a subclass of the new one:

```ruby
class Completion < New::Completion
  extend GemKit::Deprecate
  superseded_by "New::Completion", "5.0"
end
```

Both keep working, warn on use naming the caller, and register the deadline:

```
NOTE: Session#old_reset is deprecated; use Session#new_reset instead.
It will be removed in 5.0
Session#old_reset called from app.rb:12.
```

Use `:none` when there genuinely is no replacement. `Gem::Deprecate.skip_during`
silences the warnings, so a suite can exercise the old path in quiet.

## Enforcing — gem_kit-release

Installing it registers one `gem` command. There is nothing to wire up — no
Rakefile, no binstubs:

```sh
gem kit setup                 # write DEPRECATIONS.md and RELEASE.md into your project
gem kit bump minor            # move the version
gem kit changelog --write     # have an AI CLI write the entry
gem kit changelog             # lint it
gem kit deprecations          # what is still outstanding
gem kit release --dry-run     # run the gates
gem kit tag --push            # tag it
```

| Command | What it does |
| --- | --- |
| `gem kit setup` | Writes DEPRECATIONS.md and RELEASE.md, rendered for your gem's name and versions. A generator, so `--force`, `--skip` and `--pretend` all work. |
| `gem kit bump <major\|minor\|patch>` | Rewrites the version file. Refuses to bump onto a deprecation deadline; `--force` overrides. |
| `gem kit changelog [VERSION]` | Lints CHANGELOG.md. With a version, checks that version is ready to release. |
| `gem kit changelog --write` | Hands the entry to the configured AI CLI. |
| `gem kit deprecations [VERSION]` | Lists what is outstanding. With a version, fails if any come due — a CI gate. |
| `gem kit release [--dry-run]` | Gates, then builds and pushes. |
| `gem kit tag [--push]` | Tags `v<version>`, refusing if it exists. |

Everything sits behind one `gem` command rather than six, so nothing here can
collide with a command RubyGems ships now or adds later — `gem check`,
`gem build`, `gem push` and `gem setup` all already exist.

The command line is [Thor](https://github.com/rails/thor), so `gem kit` lists
the commands and `gem kit help <command>` prints one command's arguments and
options. `gem kit setup` is a `Thor::Group` generator — the same machinery
behind `rails generate` — which is where its `create` / `identical` /
`conflict` reporting and its `--force`, `--skip` and `--pretend` come from.

Everything is read out of your `.gemspec`. Override only what cannot be
inferred:

```ruby
GemKit::Release.configure do |config|
  config.changelog        = "HISTORY.md"   # default: CHANGELOG.md
  config.version_file     = "lib/x.rb"     # default: lib/<name>/version.rb
  config.require_path     = "x"            # default: <name>, hyphens as slashes
  config.test_command     = "bin/test"
  config.changelog_writer = "claude"       # the CLI that writes the entry
end
```

### In a repository with more than one gemspec

Like this one. Every command takes `--gem`, and refuses to guess without it:

```sh
$ gem kit changelog
2 gemspecs in /home/you/src/gem_kit (gem_kit-release, gem_kit); name one with --gem

$ gem kit changelog --gem gem_kit
CHANGELOG.md is clean.
```

## Extending it

`gem kit` takes commands from other gems. `GemKit::Release.plugin` is the seam:

```ruby
# lib/gem_kit/plugin.rb, in a gem of your own
require "gem_kit/release/cli"

GemKit::Release.plugin do
  desc "lint", "Check this gem for the things gems get wrong"
  def lint = GemKit::Plugin::Lint.new(options).call
end
```

The block is evaluated on the Thor class, so the whole Thor DSL is in scope —
`desc`, `long_desc`, `method_option`, `map`, and `register` for a `Thor::Group`
generator. A command added this way is indistinguishable from a built-in one:
it appears in `gem kit`, takes `--gem`, and gets a help page.

Ship a `lib/rubygems_plugin.rb` that requires your file and RubyGems loads it on
every `gem` invocation, the same way this gem is loaded. See
[gem_kit-plugin](https://github.com/n-at-han-k/gem_kit-plugin) for a worked
example.

## Layout

```
lib/gem_kit.rb              gem_kit
lib/gem_kit/deprecate.rb
lib/gem_kit/release.rb      gem_kit-release
lib/gem_kit/release/
lib/rubygems_plugin.rb
template/                   the gem template this repository used to be
```

One `Gemfile`, one `Gemfile.lock`, one `gemset.nix`, one `flake.nix` and one
`lefthook.yml` cover both gems. The dependencies are listed in the Gemfile
outright rather than through `gemspec`, which is the only sane answer when two
gemspecs share one bundle — and, separately, what `bundlerEnv` needs, since it
resolves against a store directory holding only a Gemfile and a lockfile.

Each gemspec names its own files rather than globbing `lib/**/*.rb`, because a
glob would put the whole release toolchain inside the runtime gem.

## Template

`template/` holds the gem template this repository started as: clone it, run
`bin/01-rename-gem`, and you have a gem.

## Development

```sh
direnv allow      # or: nix develop
bin/test
```

## License

MIT
