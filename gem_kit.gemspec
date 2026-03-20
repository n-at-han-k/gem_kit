# frozen_string_literal: true

require_relative "lib/gem_kit/version"

Gem::Specification.new do |spec|
  spec.name = "gem_kit"
  spec.version = GemKit::VERSION
  spec.authors = ["Nathan K"]
  spec.email = ["nathankidd@hey.com"]

  spec.summary = "Dynamic gem template"

  spec.description = <<~DESC
    Clone the repo and run bin/rename-gem and you have a gem.
  DESC

  spec.homepage = "https://github.com/n-at-han-k/gem-kit"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["documentation_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features|data)/}) }
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
end
