# frozen_string_literal: true

require "rubygems"

module GemKit
  module Release
    # What the tooling needs to know about the project it is running in.
    #
    # Almost all of it is already declared in the project's .gemspec — name,
    # version, and (through `require_relative`) where the version constant
    # lives. So the normal case is no configuration at all: point it at a
    # directory and it works out the rest.
    #
    #   project = GemKit::Release::Project.detect
    #   project.name        # => "brute"
    #   project.version     # => Gem::Version.new("4.1.0")
    #   project.version_file # => ".../lib/brute/version.rb"
    #
    # Anything that cannot be inferred is an override:
    #
    #   GemKit::Release.configure do |config|
    #     config.changelog = "HISTORY.md"
    #     config.test_command = "bin/test"
    #   end
    class Project
      class NotFound < StandardError; end

      # More than one gemspec and nothing to choose between them. A monorepo
      # has to say which gem it means.
      class Ambiguous < StandardError; end

      # Overridable settings. Each is nil until set, and nil means "infer".
      Config = Struct.new(:changelog, :version_file, :require_path, :test_command,
                          :changelog_writer, keyword_init: true)

      # `name` picks one gem out of a repository that holds several — matched
      # against the gemspec's filename, so `--gem gem_kit` finds
      # gem_kit.gemspec and not gem_kit-release.gemspec.
      def self.detect(dir = Dir.pwd, name: nil, config: GemKit::Release.config)
        gemspecs = Dir[File.join(dir, "*.gemspec")].sort
        raise NotFound, "no .gemspec in #{dir}" if gemspecs.empty?

        if name
          match = gemspecs.find { |path| File.basename(path, ".gemspec") == name }
          raise NotFound, "no #{name}.gemspec in #{dir}" if match.nil?

          return new(match, config: config)
        end

        # Silently picking the first would mean bumping the wrong gem's version
        # and only finding out on release.
        if gemspecs.size > 1
          names = gemspecs.map { |path| File.basename(path, ".gemspec") }
          raise Ambiguous, "#{gemspecs.size} gemspecs in #{dir} (#{names.join(", ")}); " \
                           "name one with --gem"
        end

        new(gemspecs.first, config: config)
      end

      attr_reader :root, :gemspec_path, :config

      def initialize(gemspec_path, config: GemKit::Release.config)
        @gemspec_path = File.expand_path(gemspec_path)
        @root         = File.dirname(@gemspec_path)
        @config       = config
      end

      # The evaluated gemspec. Loaded from the project root, because a gemspec
      # typically require_relative's its own version file.
      def spec
        @spec ||= Dir.chdir(root) { Gem::Specification.load(gemspec_path) } or
          raise NotFound, "could not load #{gemspec_path}"
      end

      def name = spec.name

      def version = Gem::Version.new(spec.version.to_s)

      # The next major version — the usual deadline for a deprecation. Written
      # "5.0" rather than "5": it reads as a version in prose and in a
      # declaration, and Gem::Version treats the two as equal anyway.
      def next_major_version
        "#{version.segments.first.to_i + 1}.0"
      end

      # Every gemspec beside this one, this one included. A repository with
      # more than one releases each gem on its own schedule, and several things
      # below have to know that.
      def siblings
        @siblings ||= Dir[File.join(root, "*.gemspec")].size
      end

      def multi_gem? = siblings > 1

      # One changelog per gem. A shared file cannot work: the release gate asks
      # whether the version being cut is the *topmost* released section, and
      # two gems interleaved in one file means the older one never is — so the
      # second gem could never be released.
      def changelog_path
        File.expand_path(config.changelog || default_changelog, root)
      end

      def default_changelog
        multi_gem? ? "CHANGELOG-#{name}.md" : "CHANGELOG.md"
      end

      # `v1.2.3` says which version but not which gem, which is fine until a
      # repository holds two of them at the same version.
      def tag_prefix
        multi_gem? ? "#{name}-v" : "v"
      end

      # lib/gem_kit/release/version.rb for "gem_kit-release", lib/brute/version.rb
      # for "brute" — the convention every `bundle gem` project follows.
      def version_file
        File.expand_path(config.version_file || File.join("lib", *name.split("-"), "version.rb"), root)
      end

      # An ERB template beside the version file, if the project generates it.
      def version_template
        candidate = "#{version_file}.erb"
        candidate if File.exist?(candidate)
      end

      # What to require so that deprecation declarations register themselves.
      # "gem_kit-release" -> "gem_kit/release".
      def require_path
        config.require_path || name.tr("-", "/")
      end

      # Load the library, so Deprecate's registry reflects this project.
      def load!
        $LOAD_PATH.unshift(File.join(root, "lib")) unless $LOAD_PATH.include?(File.join(root, "lib"))
        require require_path
        true
      rescue LoadError => error
        warn "gem_kit-release: could not require #{require_path.inspect} (#{error.message});" \
             " deprecations will not be detected"
        false
      end

      def test_command = config.test_command || "bin/test"

      def changelog_writer = config.changelog_writer || "claude"
    end
  end
end

__END__

describe "gem_kit/release/project" do
  require "tmpdir"

  # A throwaway gem laid out the conventional way.
  with_project = lambda do |name: "demo", version: "1.2.3", &block|
    Dir.mktmpdir do |dir|
      path = name.split("-")
      FileUtils.mkdir_p(File.join(dir, "lib", *path))
      File.write(File.join(dir, "lib", *path, "version.rb"), <<~RUBY)
        module #{path.map { |p| p.split("_").map(&:capitalize).join }.join("::")}
          VERSION = "#{version}"
        end
      RUBY
      File.write(File.join(dir, "#{name}.gemspec"), <<~RUBY)
        require_relative "lib/#{path.join("/")}/version"
        Gem::Specification.new do |spec|
          spec.name = "#{name}"
          spec.version = "#{version}"
          spec.authors = ["x"]
          spec.summary = "x"
          spec.files = []
        end
      RUBY
      block.call(dir)
    end
  end

  it "detects the gemspec and reads name and version from it" do
    with_project.call do |dir|
      project = GemKit::Release::Project.detect(dir)
      project.name.should == "demo"
      project.version.should == Gem::Version.new("1.2.3")
    end
  end

  it "raises when there is no gemspec" do
    Dir.mktmpdir do |dir|
      lambda { GemKit::Release::Project.detect(dir) }.should.raise(GemKit::Release::Project::NotFound)
    end
  end

  it "infers the version file from the gem name, hyphens as directories" do
    with_project.call(name: "gem_kit-release") do |dir|
      GemKit::Release::Project.detect(dir).version_file
        .should == File.join(dir, "lib/gem_kit/release/version.rb")
    end
  end

  it "infers the require path from the gem name" do
    with_project.call(name: "gem_kit-release") do |dir|
      GemKit::Release::Project.detect(dir).require_path.should == "gem_kit/release"
    end
  end

  it "defaults the changelog to CHANGELOG.md in the project root" do
    with_project.call do |dir|
      project = GemKit::Release::Project.detect(dir)
      project.multi_gem?.should.be.false
      project.changelog_path.should == File.join(dir, "CHANGELOG.md")
      project.tag_prefix.should == "v"
    end
  end

  # One changelog and one tag namespace per gem, because a repository with two
  # gems releases them separately.
  it "gives each gem its own changelog and tag prefix when there are several" do
    with_project.call(name: "demo") do |dir|
      File.write(File.join(dir, "other.gemspec"), <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "other"
          spec.version = "9.9.9"
          spec.authors = ["x"]
          spec.summary = "x"
          spec.files = []
        end
      RUBY

      project = GemKit::Release::Project.detect(dir, name: "demo")
      project.multi_gem?.should.be.true
      project.changelog_path.should == File.join(dir, "CHANGELOG-demo.md")
      project.tag_prefix.should == "demo-v"

      GemKit::Release::Project.detect(dir, name: "other").changelog_path
        .should == File.join(dir, "CHANGELOG-other.md")
    end
  end

  it "an explicit changelog still overrides, in either kind of repository" do
    with_project.call(name: "demo") do |dir|
      File.write(File.join(dir, "other.gemspec"), "Gem::Specification.new { |s| s.name = \"other\" }")

      config = GemKit::Release::Project::Config.new(changelog: "HISTORY.md")
      GemKit::Release::Project.detect(dir, name: "demo", config: config).changelog_path
        .should == File.join(dir, "HISTORY.md")
    end
  end

  it "bumps to the next major for the default deprecation deadline" do
    with_project.call(version: "4.1.0") do |dir|
      GemKit::Release::Project.detect(dir).next_major_version.should == "5.0"
    end
  end

  it "finds an ERB version template when the project generates its version file" do
    with_project.call do |dir|
      GemKit::Release::Project.detect(dir).version_template.should.be.nil
      File.write(File.join(dir, "lib/demo/version.rb.erb"), "x")
      GemKit::Release::Project.detect(dir).version_template
        .should == File.join(dir, "lib/demo/version.rb.erb")
    end
  end

  it "picks one gem out of a repository holding several" do
    with_project.call(name: "demo") do |dir|
      File.write(File.join(dir, "other.gemspec"), <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "other"
          spec.version = "9.9.9"
          spec.authors = ["x"]
          spec.summary = "x"
          spec.files = []
        end
      RUBY

      GemKit::Release::Project.detect(dir, name: "demo").name.should == "demo"
      GemKit::Release::Project.detect(dir, name: "other").version.should == Gem::Version.new("9.9.9")
    end
  end

  it "refuses to guess between several gemspecs" do
    with_project.call(name: "demo") do |dir|
      File.write(File.join(dir, "other.gemspec"), "Gem::Specification.new { |s| s.name = \"other\" }")

      lambda { GemKit::Release::Project.detect(dir) }
        .should.raise(GemKit::Release::Project::Ambiguous)
    end
  end

  it "reports a named gem that is not here" do
    with_project.call(name: "demo") do |dir|
      lambda { GemKit::Release::Project.detect(dir, name: "nope") }
        .should.raise(GemKit::Release::Project::NotFound)
    end
  end

  it "takes overrides from the config" do
    with_project.call do |dir|
      config = GemKit::Release::Project::Config.new(changelog: "HISTORY.md", test_command: "rake")
      project = GemKit::Release::Project.detect(dir, config: config)
      project.changelog_path.should == File.join(dir, "HISTORY.md")
      project.test_command.should == "rake"
    end
  end
end
