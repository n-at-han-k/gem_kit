# frozen_string_literal: true

require_relative "../gem_kit"
require_relative "release/version"
require_relative "release/changelog"
require_relative "release/project"
require_relative "release/version_file"
require_relative "release/gate"

module GemKit
  # Versioning, changelog and deprecation gates for Ruby gems.
  #
  # The premise: a deprecation is a dated promise — it names its replacement
  # and the version the old name stops existing in — and a release is only
  # honest if it keeps every promise that has come due and documents what
  # changed. Both are checkable, so neither should depend on anyone
  # remembering.
  #
  # In a Rakefile, which is the whole integration:
  #
  #   require "gem_kit/release/tasks"
  #
  # Everything else is inferred from the project's .gemspec. Override only
  # what cannot be:
  #
  #   GemKit::Release.configure do |config|
  #     config.changelog        = "HISTORY.md"
  #     config.test_command     = "bin/test"
  #     config.changelog_writer = "claude"
  #   end
  module Release
    def self.config
      @config ||= Project::Config.new
    end

    def self.configure
      yield config
      config
    end

    # The project the tooling is running in. `name` picks one out of a
    # repository holding several gemspecs — this one, for instance.
    def self.project(dir = Dir.pwd, name: nil)
      Project.detect(dir, name: name)
    end

    def self.gate(dir = Dir.pwd, name: nil)
      Gate.new(project(dir, name: name))
    end

    # Reset configuration — for tests.
    def self.reset!
      @config = nil
    end
  end
end

__END__

describe "gem_kit/release" do
  it "exposes a configurable, resettable config" do
    begin
      GemKit::Release.configure { |c| c.changelog = "HISTORY.md" }
      GemKit::Release.config.changelog.should == "HISTORY.md"
    ensure
      GemKit::Release.reset!
    end

    GemKit::Release.config.changelog.should.be.nil
  end

  it "detects a named gem out of this repository" do
    root = File.expand_path("../..", __dir__)

    release = GemKit::Release.project(root, name: "gem_kit-release")
    release.name.should == "gem_kit-release"
    release.version.should == Gem::Version.new(GemKit::Release::VERSION)
    release.require_path.should == "gem_kit/release"

    runtime = GemKit::Release.project(root, name: "gem_kit")
    runtime.name.should == "gem_kit"
    runtime.require_path.should == "gem_kit"
  end

  it "refuses to guess which gem in this repository is meant" do
    lambda { GemKit::Release.project(File.expand_path("../..", __dir__)) }
      .should.raise(GemKit::Release::Project::Ambiguous)
  end
end
