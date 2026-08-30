# frozen_string_literal: true

# Test support shared by the CLI specs. Not shipped: the gemspec's file list
# covers lib/ only.
#
#   describe "..." do
#     extend GemKitReleaseSpec
#     ...
#   end

require "tmpdir"
require "fileutils"
require "stringio"

# Keeps the throwaway projects below from finding a repository above Dir.tmpdir.
require_relative "git_isolation"

require_relative "../../lib/gem_kit/release/cli"

module GemKitReleaseSpec
  # A throwaway gem laid out the conventional way, with a clean changelog
  # unless asked otherwise.
  def with_gem(version: "1.2.3", changelog: :clean, second_gem: false)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib/demo"))
      File.write(File.join(dir, "lib/demo/version.rb"), %(module Demo\n  VERSION = "#{version}"\nend\n))
      File.write(File.join(dir, "lib/demo.rb"), "require_relative 'demo/version'\n")
      File.write(File.join(dir, "demo.gemspec"), <<~RUBY)
        require_relative "lib/demo/version"
        Gem::Specification.new do |spec|
          spec.name = "demo"
          spec.version = Demo::VERSION
          spec.authors = ["x"]
          spec.summary = "x"
          spec.files = []
        end
      RUBY

      if second_gem
        File.write(File.join(dir, "other.gemspec"), <<~RUBY)
          Gem::Specification.new do |spec|
            spec.name = "other"
            spec.version = "#{version}"
            spec.authors = ["x"]
            spec.summary = "x"
            spec.files = []
          end
        RUBY
      end

      if changelog == :clean
        File.write(File.join(dir, "CHANGELOG.md"), <<~MD)
          # Changelog

          ## [Unreleased]

          ## [#{version}] - 2026-01-01

          ### Added

          - A thing.
        MD
      end

      yield dir
    end
  end

  # Run one CLI invocation the way `gem kit` does — through the dry-cli
  # registry, so argument and option parsing is covered too. Returns
  # [status, stdout, stderr] with the deprecation registry isolated.
  #
  # `deprecations` seeds the registry: [[name, replacement, removed_in], ...]
  def invoke(arguments, dir, deprecations: [])
    saved = GemKit::Deprecate.registry.dup
    GemKit::Deprecate.registry.clear
    deprecations.each do |name, replacement, removed_in|
      GemKit::Deprecate.register(name: name, replacement: replacement, removed_in: removed_in)
    end

    out, err = StringIO.new, StringIO.new
    saved_out, saved_err = $stdout, $stderr
    $stdout, $stderr = out, err

    begin
      status = Dir.chdir(dir) { GemKit::Release.run(arguments, out: out, err: err) }
    ensure
      $stdout, $stderr = saved_out, saved_err
      GemKit::Deprecate.registry.replace(saved)
    end

    [status, out.string, err.string]
  end
end
