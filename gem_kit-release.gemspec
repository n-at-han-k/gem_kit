# frozen_string_literal: true

require_relative "lib/gem_kit/release/version"

Gem::Specification.new do |spec|
  spec.name     = "gem_kit-release"
  spec.version  = GemKit::Release::VERSION
  spec.license  = "MIT"
  spec.summary  = "Versioning, changelog and deprecation gates for Ruby gems"

  spec.description = <<~DESCRIPTION
    The maintainer's half of gem_kit: one RubyGems command, `gem kit`, with
    subcommands for bumping the version, writing and linting the changelog,
    listing outstanding deprecations, releasing and tagging.

    It keeps the promises gem_kit records. `gem kit bump` refuses to move onto
    a deprecation's removal version while the old name is still in the tree,
    and `gem kit release` refuses to ship a version with an unkept promise or
    no changelog entry of its own.

    Everything is read from the .gemspec in the working directory, so the
    normal case needs no configuration at all.
  DESCRIPTION

  spec.author   = "Nathan Kidd"
  spec.email    = "nathanblenheimkidd@gmail.com"
  spec.homepage = "https://github.com/n-at-han-k/gem_kit"

  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "source_code_uri"       => spec.homepage,
    "changelog_uri"         => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri"       => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true",
  }

  # The release subtree only. lib/gem_kit.rb and lib/gem_kit/deprecate.rb
  # belong to the gem_kit gem, which this one depends on.
  spec.files = Dir[
    "lib/gem_kit/release.rb",
    "lib/gem_kit/release/**/*.rb",
    "lib/gem_kit/release/templates/*.erb",
    "lib/rubygems_plugin.rb",
    "lib/rubygems/commands/*.rb",
  ] + ["LICENSE", "README.md"]

  spec.require_paths = ["lib"]

  spec.add_dependency "gem_kit", ">= 0.1", "< 1.0"
  spec.add_dependency "thor", "~> 1.3"
end
