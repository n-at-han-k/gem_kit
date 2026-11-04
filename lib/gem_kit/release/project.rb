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

      def lockfile_path
        File.join(root, "Gemfile.lock")
      end

      # A Gemfile that says `gemspec` or `path: "."` puts this gem in its own
      # bundle, and the lockfile then records this gem's version. Bumping
      # without relocking leaves the two disagreeing — which bundler reports as
      # "the gemspecs for path gems changed", and refuses outright under
      # frozen mode, as bundlerEnv sets.
      def self_locked?
        return false unless File.exist?(lockfile_path)

        File.read(lockfile_path).match?(/^\s{4}#{Regexp.escape(name)} \(\d/)
      end

      # `v1.2.3` says which version but not which gem, which is fine until a
      # repository holds two of them at the same version.
      def tag_prefix
        multi_gem? ? "#{name}-v" : "v"
      end

      # lib/gem_kit/release/version.rb for "gem_kit-release", lib/brute/version.rb
      # for "brute" — the convention every `bundle gem` project follows.
      def version_file
        File.expand_path(
          config.version_file || File.join("lib", *library_segments, "version.rb"),
          root,
        )
      end

      # An ERB template beside the version file, if the project generates it.
      def version_template
        candidate = "#{version_file}.erb"
        candidate if File.exist?(candidate)
      end

      # What to require so that deprecation declarations register themselves.
      # "gem_kit-release" -> "gem_kit/release".
      def require_path
        config.require_path || library_segments.join("/")
      end

      # Where the library sits under lib/, as path segments.
      #
      # `bundle gem gem_kit-release` NESTS, treating the hyphen as a directory
      # separator: lib/gem_kit/release.rb, module GemKit::Release. That is the
      # common case and the one assumed here first.
      #
      # But a hyphenated name whose library is a SINGLE module does not nest.
      # `ag-ui` is lib/ag_ui.rb holding `module AgUi` — hyphen as underscore —
      # and the nested form names lib/ag/ui.rb, a file that was never there.
      #
      # A third belongs to bindings. `oo7-rb` and `sqlite3-ruby` are a library
      # name wearing a suffix that says which language binds it, and the library
      # underneath drops it: lib/oo7.rb holding `module Oo7`, with
      # lib/oo7/version.rb beside it. Often the suffix is only there because
      # RubyGems would not give up the bare name. The nested form names
      # lib/oo7/rb.rb and the flat one lib/oo7_rb.rb, neither of which was ever
      # there, so without this a binding gem cannot be bumped at all.
      #
      # A fourth wears that suffix after a DOT rather than a hyphen: `clippy.rb`,
      # `vue.rb`, `d3.rb`. RubyGems allows a dot in a name, and the convention
      # is the same as the hyphenated binding above — the library drops the
      # suffix, so lib/clippy.rb holds `module Clippy` and the version sits at
      # lib/clippy/version.rb. None of the hyphen layouts sees this: splitting
      # "clippy.rb" on "-" yields one segment that still has the dot in it, so
      # the inferred path was lib/clippy.rb/version.rb — a directory whose name
      # ends in .rb, which nothing has.
      #
      # All four are conventional and the name alone cannot tell them apart, so
      # ask the tree: whichever exists is what this project is.
      #
      # When none exists the nested form wins, because that is what
      # `bundle gem` would have produced and a project with no library yet is
      # about to become one — except for a dotted name, which `bundle gem`
      # cannot produce at all, and whose only convention is the dotted one.
      def library_segments
        layouts.find { |segments| exists_under_lib?(segments) } || default_layout
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

      private

        # The suffixes a binding gem wears, which its library drops.
        BINDING_SUFFIXES = %w[rb ruby].freeze

        # What a name could mean, most conventional first. A name with neither
        # a hyphen nor a dotted suffix in it has exactly one meaning and the
        # list says so.
        def layouts
          [*dotted_layout, nested_layout, flat_layout, *binding_layout].uniq
        end

        # Nesting is `bundle gem`'s doing and so the usual default, but
        # `bundle gem` will not take a dotted name, so there is nothing for a
        # dotted one to fall back to but itself.
        def default_layout = dotted_layout.first || nested_layout

        def nested_layout = name.split("-")

        def flat_layout = [name.tr("-", "_")]

        # [["clippy"]] for "clippy.rb"; nothing for a name with no dot, and
        # nothing for a dot that is not a language suffix, so a hypothetical
        # "foo.bar" is left to the layouts above.
        def dotted_layout
          name.split(".").then do |segments|
            if segments.length == 2 && BINDING_SUFFIXES.include?(segments.last)
              [[segments.first]]
            else
              []
            end
          end
        end

        # [["oo7"]] for "oo7-rb"; nothing for a name wearing no binding suffix,
        # and nothing for one that is only the suffix.
        def binding_layout
          nested_layout.then do |segments|
            if segments.length > 1 && BINDING_SUFFIXES.include?(segments.last)
              [segments[0..-2]]
            else
              []
            end
          end
        end

        # A layout is present if the entry file is there, or the directory it
        # would hold — a gem is free to ship lib/foo/ without lib/foo.rb.
        def exists_under_lib?(segments)
          base = File.join(root, "lib", *segments)
          File.exist?("#{base}.rb") || File.directory?(base)
        end
    end
  end
end

__END__

describe "gem_kit/release/project" do
  require "tmpdir"

  # A throwaway gem. `layout:` picks between the three conventions a hyphenated
  # name can follow: :nested is `bundle gem`'s lib/gem_kit/release, :flat is a
  # single-module gem's lib/ag_ui, and :binding is a bindings gem's lib/oo7 for
  # a gem called oo7-rb.
  with_project = lambda do |name: "demo", version: "1.2.3", layout: :nested, &block|
    Dir.mktmpdir do |dir|
      case layout
      when :flat then path = [name.tr("-", "_")]
      when :binding then path = name.split("-")[0..-2]
      when :dotted then path = [name.split(".").first]
      else path = name.split("-")
      end
      FileUtils.mkdir_p(File.join(dir, "lib", *path))

      # Nested blocks rather than `module A::B`, which is only valid once A
      # exists -- and a throwaway gem's outermost constant never does. The one
      # hyphenated name that got away with it was gem_kit-release, because this
      # process has GemKit defined already.
      constants = path.map { |segment| segment.split("_").map(&:capitalize).join }
      lines = constants.each_with_index.map { |constant, depth| "#{"  " * depth}module #{constant}" }
      lines << "#{"  " * constants.length}VERSION = #{version.inspect}"
      lines.concat(Array.new(constants.length) { |depth| "#{"  " * (constants.length - 1 - depth)}end" })

      File.write(File.join(dir, "lib", *path, "version.rb"), "#{lines.join("\n")}\n")
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

  # A hyphenated name whose library is one module: lib/ag_ui.rb, not
  # lib/ag/ui.rb. Deriving the path from the name alone named a file that was
  # never there, so `gem kit bump` could not find the version and deprecations
  # went undetected.
  it "reads an underscored single-module layout off the tree" do
    with_project.call(name: "ag-ui", layout: :flat) do |dir|
      project = GemKit::Release::Project.detect(dir)
      project.require_path.should == "ag_ui"
      project.version_file.should == File.join(dir, "lib/ag_ui/version.rb")
    end
  end

  # A bindings gem drops the suffix: oo7-rb is lib/oo7.rb and lib/oo7/version.rb,
  # which neither of the other two layouts names. Found the hard way -- the gem
  # was called oo7-rb only because RubyGems holds `oo7` for something else, and
  # `gem kit bump` then wrote to lib/oo7/rb/version.rb, a path nothing had.
  it "reads a bindings layout, whose library drops the suffix, off the tree" do
    with_project.call(name: "oo7-rb", layout: :binding) do |dir|
      project = GemKit::Release::Project.detect(dir)
      project.require_path.should == "oo7"
      project.version_file.should == File.join(dir, "lib/oo7/version.rb")
    end
  end

  it "reads a -ruby suffix the same way" do
    with_project.call(name: "sqlite3-ruby", layout: :binding) do |dir|
      project = GemKit::Release::Project.detect(dir)
      project.version_file.should == File.join(dir, "lib/sqlite3/version.rb")
    end
  end

  # The suffix is only dropped when the tree says so. A gem that genuinely nests
  # under a segment called "rb" keeps it.
  it "keeps a nested layout that really does end in rb" do
    with_project.call(name: "thing-rb", layout: :nested) do |dir|
      project = GemKit::Release::Project.detect(dir)
      project.require_path.should == "thing/rb"
      project.version_file.should == File.join(dir, "lib/thing/rb/version.rb")
    end
  end

  # A dotted suffix is the same idea as the hyphenated binding above, and the
  # one RubyGems name shape that none of the hyphen layouts can see: splitting
  # "clippy.rb" on "-" leaves the dot in the segment, so the inferred path was
  # lib/clippy.rb/version.rb -- a directory ending in .rb, which nothing has.
  it "reads a dotted bindings layout, whose library drops the suffix" do
    with_project.call(name: "clippy.rb", layout: :dotted) do |dir|
      project = GemKit::Release::Project.detect(dir)
      project.name.should == "clippy.rb"
      project.require_path.should == "clippy"
      project.version_file.should == File.join(dir, "lib/clippy/version.rb")
    end
  end

  it "reads a dotted .ruby suffix the same way" do
    with_project.call(name: "sqlite3.ruby", layout: :dotted) do |dir|
      GemKit::Release::Project.detect(dir).version_file
        .should == File.join(dir, "lib/sqlite3/version.rb")
    end
  end

  # `bundle gem` will not take a dotted name, so unlike the hyphen cases there
  # is no nested convention for an empty tree to fall back to.
  it "falls back to the dotted layout when nothing is on disk yet" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "clippy.rb.gemspec"), <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "clippy.rb"
          spec.version = "0.1.0"
          spec.authors = ["x"]
          spec.summary = "x"
          spec.files = []
        end
      RUBY
      project = GemKit::Release::Project.detect(dir)
      project.require_path.should == "clippy"
      project.version_file.should == File.join(dir, "lib/clippy/version.rb")
    end
  end

  # The entry file alone is enough: a dotted gem's lib/clippy.rb is exactly
  # what the nested layout would mistake for its own directory.
  it "recognises the dotted layout from the entry file alone" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib", "clippy.rb"), "module Clippy
end
")
      File.write(File.join(dir, "clippy.rb.gemspec"), <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "clippy.rb"
          spec.version = "0.1.0"
          spec.authors = ["x"]
          spec.summary = "x"
          spec.files = []
        end
      RUBY
      GemKit::Release::Project.detect(dir).require_path.should == "clippy"
    end
  end

  # Only a language suffix is dropped. A dot that means something else is left
  # to the hyphen layouts, so this must not become lib/foo.
  it "leaves a dot that is not a language suffix alone" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "foo.bar.gemspec"), <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "foo.bar"
          spec.version = "0.1.0"
          spec.authors = ["x"]
          spec.summary = "x"
          spec.files = []
        end
      RUBY
      GemKit::Release::Project.detect(dir).require_path.should == "foo.bar"
    end
  end

  # "release" is not a binding suffix, so a name ending in something else is
  # untouched by any of this.
  it "leaves a hyphenated name that wears no binding suffix alone" do
    with_project.call(name: "gem_kit-release", layout: :nested) do |dir|
      project = GemKit::Release::Project.detect(dir)
      project.require_path.should == "gem_kit/release"
    end
  end

  # Nesting stays the default: it is what `bundle gem` produces, so it is what
  # a project with no library yet is about to become.
  it "falls back to the nested layout when neither is on disk" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ag-ui.gemspec"), <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = "ag-ui"
          spec.version = "0.1.0"
          spec.authors = ["x"]
          spec.summary = "x"
          spec.files = []
        end
      RUBY
      GemKit::Release::Project.detect(dir).require_path.should == "ag/ui"
    end
  end

  # An explicit setting still wins over anything read off the tree.
  it "prefers a configured require path and version file" do
    with_project.call(name: "ag-ui", layout: :flat) do |dir|
      config = GemKit::Release::Project::Config.new(
        require_path: "somewhere/else",
        version_file: "lib/custom.rb",
      )
      project = GemKit::Release::Project.detect(dir, config: config)
      project.require_path.should == "somewhere/else"
      project.version_file.should == File.join(dir, "lib/custom.rb")
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

  # A gem whose own Gemfile pulls it in has its version written in the lockfile
  # as well as the version file, and both have to move together.
  it "knows whether the lockfile records this gem's own version" do
    with_project.call do |dir|
      GemKit::Release::Project.detect(dir).self_locked?.should.be.false

      File.write(File.join(dir, "Gemfile.lock"), <<~LOCK)
        PATH
          remote: .
          specs:
            demo (1.2.3)

        GEM
          remote: https://rubygems.org/
      LOCK
      GemKit::Release::Project.detect(dir).self_locked?.should.be.true
    end
  end

  it "does not mistake another gem's line in the lockfile for its own" do
    with_project.call do |dir|
      File.write(File.join(dir, "Gemfile.lock"), <<~LOCK)
        GEM
          remote: https://rubygems.org/
          specs:
            other-demo (1.0.0)
            demo-helper (2.0.0)
      LOCK
      GemKit::Release::Project.detect(dir).self_locked?.should.be.false
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
