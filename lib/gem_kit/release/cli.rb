# frozen_string_literal: true

require "thor"

# `require`, not `require_relative`: gem_kit is a separate gem, and inside an
# installed gem_kit-release there is no ../gem_kit to reach. It works in the
# monorepo, where both gems share one lib/, which is exactly why this is worth
# a comment.
require "gem_kit"
require_relative "version"
require_relative "changelog"
require_relative "project"
require_relative "version_file"
require_relative "gate"
require_relative "commands/command"
require_relative "commands/bump"
require_relative "commands/changelog"
require_relative "commands/deprecations"
require_relative "commands/release"
require_relative "commands/tag"
require_relative "generators/setup"

module GemKit
  module Release
    # The command line behind `gem kit`, on Thor.
    #
    # Thor gives us the parts a hand-rolled parser always ends up needing
    # badly: per-command help built from the `desc`/`method_option`
    # declarations, a subcommand listing, and — the reason for choosing it over
    # a plain option parser — Thor::Group and Thor::Actions, the same generator
    # machinery Rails' `rails generate` is built on. `gem kit setup` is a
    # generator, so it gets create/identical/conflict reporting and the
    # overwrite prompt without writing any of it.
    #
    #   gem kit                    the listing
    #   gem kit help bump          that command's options
    #
    # Each command here is a thin front for a plain object under CLI::; the
    # work itself is in Gate, VersionFile, Changelog and Deprecate.
    class CLI < Thor
      # The order the commands go in — printed above the command listing so
      # nobody has to guess when to commit or when to write the changelog. The
      # question the process is easy to get wrong on is exactly the one this
      # answers: the changelog is written *after* the bump, then the two are
      # committed together, and only then does release run.
      WORKFLOW = <<~TXT
        Release, in order:

          1. bin/test                        # green suite
          2. gem kit bump [SEGMENT]          # move the version, relock the Gemfile
          3. gem kit changelog --write       # AI CLI drafts this version's entry
          4. gem kit changelog [VERSION]     # lint the entry, confirm ready to release
          5. git commit -am "Release ..."    # bump + lockfile + entry, one commit
          6. gem kit release                 # gate, build, push, tag (also pushes the tag)
          7. git push                        # publish the release commit
      TXT

      class_option :gem, type: :string,
                         desc: "Which gem, in a repository holding more than one gemspec"

      # Thor asks; without it every invocation warns.
      def self.exit_on_failure? = true

      # `gem kit` with no arguments lists the commands rather than erroring.
      def self.banner(command, _namespace = nil, _subcommand = false)
        "gem kit #{command.usage}"
      end

      # Prepend the workflow to the top-level `gem kit` help. `gem kit help
      # <command>` sets subcommand=true and lands here too; that page already
      # has its own long_desc, so leave it alone.
      def self.help(shell, subcommand = false)
        shell.say(WORKFLOW) unless subcommand
        shell.say unless subcommand
        super
      end

      # Short forms for the three typed most often.
      map "log"  => :changelog,
          "deps" => :deprecations,
          "init" => :setup

      register(Generators::Setup, "setup", "setup",
               "Copy DEPRECATIONS.md and RELEASE.md into this project")

      desc "bump [SEGMENT]", "Move the gem version, refusing to bump onto a deprecation deadline"
      long_desc <<~TXT
        Rewrites the gem's version file — by rendering its .erb template if there is
        one, otherwise by substituting the version literal in place.

        Refuses to bump onto a deprecation deadline. A deprecation names the version
        the old name stops existing in; bumping to that version while the old name is
        still in the tree breaks that promise. Remove the deprecated code first, or
        pass --force, which says what it is overriding.
      TXT
      method_option :force, type: :boolean, default: false, aliases: "-f",
                            desc: "Bump even when a deprecation comes due"
      def bump(segment = "patch")
        Commands::Bump.new(options).call(segment)
      end

      desc "changelog [VERSION]", "Lint CHANGELOG.md, or have an AI CLI write this version's entry"
      long_desc <<~TXT
        Checks CHANGELOG.md against Keep a Changelog: the title, that every heading is
        `## [Unreleased]` or `## [1.2.3] - YYYY-MM-DD`, that versions are valid, dated,
        unique and ordered newest-first, and that ### sections are one of Added,
        Changed, Deprecated, Removed, Fixed, Security — none of them empty.

        Given a version, it also asks whether that version has a non-empty section of
        its own sitting at the top of the released list.

        With --write, hands the job to the CLI named by config.changelog_writer
        (default: claude). Review what it writes.
      TXT
      method_option :write, type: :boolean, default: false, aliases: "-w",
                            desc: "Ask the configured AI CLI to write this version's entry"
      def changelog(version = nil)
        Commands::Changelog.new(options).call(version)
      end

      desc "deprecations [VERSION]", "List the deprecations this gem has not yet honoured"
      long_desc <<~TXT
        A deprecation names its replacement and the version the old name stops
        existing in. This lists the promises still outstanding, with the source
        location of each declaration.

        Given a version, it lists only what comes due there and fails if anything
        does, which is what makes it usable as a gate in CI.
      TXT
      def deprecations(version = nil)
        Commands::Deprecations.new(options).call(version)
      end

      desc "release", "Gate, build, push and tag this gem"
      long_desc <<~TXT
        Three gates, all before `gem build` runs:

        the changelog must have a non-empty, correctly formatted section for this
        version, sitting at the top of the released list; nothing promised to
        disappear in this version may still be in the tree; and the working tree
        must be committed, because a gem built from uncommitted files is a gem
        whose source exists nowhere.

        Then builds the gemspec, pushes it, and tags the release — after the push,
        so a tag never names a version that failed to publish. Requires RubyGems
        push credentials.

        --dry-run runs the gates and stops, which is what belongs in CI.
      TXT
      method_option :dry_run, type: :boolean, default: false, aliases: "-n",
                              desc: "Run the gates and stop"
      method_option :tag, type: :boolean, default: true,
                          desc: "Tag the release and push the tag (--no-tag to skip)"
      method_option :allow_dirty, type: :boolean, default: false,
                                  desc: "Release even with uncommitted changes"
      def release
        Commands::Release.new(options).call
      end

      desc "tag", "Tag the current version in git"
      long_desc <<~TXT
        Creates the annotated tag <prefix><version> — v4.1.0 by default — for the
        version in the gem's version file, refusing if that tag already exists.

        The tag is what the next changelog is written against, so a missing one makes
        the following release harder to describe.
      TXT
      method_option :push, type: :boolean, default: false, aliases: "-p",
                           desc: "Push the tag to origin"
      method_option :prefix, type: :string,
                             desc: "Tag name prefix (default: v, or <gem>-v in a multi-gem repository)"
      def tag
        Commands::Tag.new(options).call
      end
    end

    # The extension seam. A plugin gem adds commands to `gem kit` by reopening
    # the CLI through this, which is a documented entry point rather than a
    # class_eval someone reverse-engineered:
    #
    #   # lib/gem_kit/plugin.rb, in a gem of your own
    #   require "gem_kit/release/cli"
    #
    #   GemKit::Release.plugin do
    #     desc "lint", "Check this gem for the things gems get wrong"
    #     def lint = GemKit::Plugin::Lint.new(options).call
    #   end
    #
    # The block is evaluated on the Thor class, so everything Thor offers is
    # in scope: `desc`, `long_desc`, `method_option`, `map`, and `register` for
    # a Thor::Group generator. Commands added this way are indistinguishable
    # from the built-in ones — they appear in `gem kit`, take `--gem`, and get
    # a help page.
    #
    # Loading is the plugin's own business: ship a lib/rubygems_plugin.rb that
    # requires your file, and RubyGems will load it on every `gem` invocation,
    # the same way this gem gets loaded.
    def self.plugin(&block)
      CLI.class_eval(&block)
      CLI
    end

    # Run one invocation. Returns an exit status rather than exiting, so the
    # `gem kit` bridge can hand it to terminate_interaction and the specs can
    # assert on it.
    def self.run(arguments, out: $stdout, err: $stderr)
      CLI.start(arguments)
      0
    rescue Failure, Project::NotFound, Project::Ambiguous => failure
      # NotFound and Ambiguous are rescued here rather than only in
      # Commands::Command#project, because a Project is lazy: `detect` succeeds
      # on a gemspec that exists, and the failure surfaces later, from whichever
      # command first asks for `version` or `spec`. Catching it at the entry
      # point is the only place that covers all of them.
      err.puts(failure.message)
      1
    rescue SystemExit => exit_exception
      # Thor exits on an unknown command or a missing required argument.
      exit_exception.status
    end
  end
end

__END__

describe "gem_kit/release/cli" do
  require_relative "../../../spec/support/gem_kit_release_spec"
  extend GemKitReleaseSpec

  it "lists every command with its description" do
    with_gem do |dir|
      _status, out, _err = invoke([], dir)

      %w[setup bump changelog deprecations release tag].each { |name| out.should.match(/#{name}/) }
      out.should.match(/Move the gem version/)
    end
  end

  # The order between `bump` and `release` — when to write the changelog and
  # when to commit — is exactly the question the numbered list answers, so
  # the top-level help has to print it.
  it "prints the numbered workflow above the command listing" do
    with_gem do |dir|
      _status, out, _err = invoke([], dir)

      out.should.match(/Release, in order:/)
      out.should.match(/1\. bin\/test/)
      out.should.match(/2\. gem kit bump/)
      out.should.match(/5\. git commit/)
      out.should.match(/6\. gem kit release/)
      out.should.match(/7\. git push/)
      # The workflow lands above "Commands:", not swallowed by it.
      out.index("Release, in order:").should < out.index("Commands:")
    end
  end

  # `gem kit help <command>` already has its own long_desc; the workflow
  # belongs on the top-level page only.
  it "does not repeat the workflow on a per-command help page" do
    with_gem do |dir|
      _status, out, _err = invoke(["help", "bump"], dir)
      out.should.not.match(/Release, in order:/)
    end
  end

  it "names the commands `gem kit <command>`, not the running program" do
    with_gem do |dir|
      _status, out, _err = invoke([], dir)

      out.should.match(/gem kit bump/)
      out.should.not.match(/^\s+rspec /)
    end
  end

  it "prints a command's options and long description for help" do
    with_gem do |dir|
      _status, out, _err = invoke(["help", "bump"], dir)

      out.should.match(/gem kit bump/)
      out.should.match(/SEGMENT/)
      out.should.match(/--force/)
      out.should.match(/deprecation deadline/)
    end
  end

  # A gemspec that exists but does not parse fails inside Gem::Specification
  # rather than in Project.detect, which is a different place than it looks.
  it "reports an unparseable gemspec instead of raising" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "demo.gemspec"),
                 %(Gem::Specification.new do |spec|\n  spec.description = <<~D\n    unterminated\n))

      status, _out, err = invoke(["release", "--dry-run"], dir)

      status.should == 1
      err.should.match(/could not load .*demo\.gemspec/)
    end
  end

  it "fails on an unknown command" do
    with_gem do |dir|
      invoke(["nonsense"], dir).first.should.not == 0
    end
  end

  # What a plugin gem does. The command has to be indistinguishable from a
  # built-in one, or the seam is not worth documenting.
  it "takes a command from a plugin" do
    GemKit::Release.plugin do
      desc "hello NAME", "Say hello from a plugin"
      def hello(name) = $stdout.puts("hello #{name} (#{options[:gem] || "no --gem"})")
    end

    begin
      with_gem do |dir|
        status, out, _err = invoke(["hello", "world"], dir)
        status.should == 0
        out.should.match(/hello world/)

        # The class options reach it too.
        _status, out, _err = invoke(["hello", "world", "--gem", "demo"], dir)
        out.should.match(/hello world \(demo\)/)

        # And it is listed and documented like the rest.
        _status, listing, _err = invoke([], dir)
        listing.should.match(/gem kit hello NAME/)
        listing.should.match(/Say hello from a plugin/)
      end
    ensure
      GemKit::Release::CLI.remove_command("hello")
    end
  end

  it "hands the plugin the whole Thor DSL, generators included" do
    generator = Class.new(Thor::Group) do
      include Thor::Actions
      def self.banner = "gem kit scaffold"
      def report = $stdout.puts("scaffolded")
    end
    Object.const_set(:PluginScaffoldGenerator, generator) unless defined?(PluginScaffoldGenerator)

    GemKit::Release.plugin do
      register(PluginScaffoldGenerator, "scaffold", "scaffold", "Scaffold something")
    end

    begin
      with_gem do |dir|
        status, out, _err = invoke(["scaffold"], dir)
        status.should == 0
        out.should.match(/scaffolded/)
      end
    ensure
      GemKit::Release::CLI.remove_command("scaffold")
    end
  end
end
