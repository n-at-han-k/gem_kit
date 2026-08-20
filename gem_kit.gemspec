# frozen_string_literal: true

require_relative "lib/gem_kit/version"

Gem::Specification.new do |spec|
  spec.name     = "gem_kit"
  spec.version  = GemKit::VERSION
  spec.license  = "MIT"
  spec.summary  = "A deprecation DSL that makes a removal deadline enforceable"

  spec.description = <<~DESCRIPTION
    A deprecation is a dated promise: it names its replacement and the version
    the old name stops existing in. GemKit::Deprecate declares that promise --
    `deprecate` for a method, `superseded_by` for a renamed constant -- warns
    on use naming the caller, and registers the deadline so it can be checked.

    Built on Gem::Deprecate, so the message format and Gem::Deprecate.skip_during
    work as they already do. No dependencies beyond RubyGems' own: a library
    that deprecates a name should not thereby acquire a release toolchain.

    The checking lives in the gem_kit-release gem, which reads this registry.
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

  # Named by file, not by `lib/**/*.rb`: two gems share this lib/, the way
  # remind's three share theirs, and a glob would put the whole release
  # toolchain inside the runtime gem.
  spec.files = [
    "lib/gem_kit.rb",
    "lib/gem_kit/deprecate.rb",
    "lib/gem_kit/version.rb",
    "LICENSE",
    "README.md",
  ]

  spec.require_paths = ["lib"]
end
