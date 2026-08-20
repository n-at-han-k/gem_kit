# frozen_string_literal: true

require "rubygems/command"

module Gem
  module Commands
    # `gem kit <subcommand>` — the only command this gem registers.
    #
    # One registration rather than six keeps the toolchain under a name that is
    # obviously ours, leaves `gem help commands` readable, and means nothing
    # here can collide with a command RubyGems adds later.
    #
    # This class is a bridge and nothing else: it hands the argv to the dry-cli
    # registry, which owns the parsing and the help pages, and turns the result
    # into a RubyGems exit. handle_options is deliberately inert — parsing here
    # would swallow flags meant for a subcommand.
    class KitCommand < Gem::Command
      def initialize
        super("kit", "Versioning, changelog and deprecation gates for this gem")
      end

      def arguments
        <<~TXT
          setup         copy DEPRECATIONS.md and RELEASE.md into this project
          bump          move the version, refusing to bump onto a deprecation deadline
          changelog     lint CHANGELOG.md, or have an AI CLI write this version's entry
          deprecations  list the deprecations this gem has not yet honoured
          release       gate, build and push this gem
          tag           tag the current version in git
        TXT
      end

      def usage = "#{program_name} SUBCOMMAND [options]"

      def defaults_str = "(lists the subcommands)"

      def description
        <<~TXT
          A deprecation is a dated promise: it names its replacement and the version
          the old name stops existing in. These commands keep those promises — `bump`
          refuses to move onto a deadline, and `release` refuses to ship a version with
          an unkept promise or no changelog entry of its own.

          Everything is read from the .gemspec in the working directory, so there is
          nothing to configure in the common case.

          Run `gem kit SUBCOMMAND --help` for one subcommand's arguments, options and
          examples.
        TXT
      end

      # Inert on purpose: the dry-cli registry parses the argv, including the
      # subcommand's own flags.
      def handle_options(args)
        @argv = args.dup
      end

      def execute
        # require_relative, not require: this resolves whether or not the gem
        # is installed, which keeps the command testable from the repo.
        require_relative "../../gem_kit/release/cli"

        terminate_interaction(GemKit::Release.run(@argv || []))
      end
    end
  end
end

__END__

describe "rubygems/commands/kit_command" do
  require_relative "../../../spec/support/gem_kit_release_spec"
  extend GemKitReleaseSpec

  it "dispatches to a subcommand, passing its arguments through" do
    with_gem do |dir|
      status, out, _err = invoke(["bump", "minor"], dir)

      status.should == 0
      out.should.match(/1\.2\.3 -> 1\.3\.0/)
      File.read(File.join(dir, "lib/demo/version.rb")).should.match(/"1\.3\.0"/)
    end
  end

  it "passes flags through to the subcommand's own parser" do
    with_gem do |dir|
      status, out, _err = invoke(["bump", "major", "--force"], dir,
                                 deprecations: [["Old", "New", "2.0"]])

      status.should == 0
      out.should.match(/--force given/)
    end
  end

  it "propagates a subcommand's failure as a non-zero status" do
    with_gem do |dir|
      status, _out, err = invoke(["changelog", "9.9.9"], dir)
      status.should == 1
      err.should.match(/no section for 9\.9\.9/)
    end
  end

  it "describes itself for `gem help kit`" do
    command = Gem::Commands::KitCommand.new

    command.command.should == "kit"
    command.usage.should.match(/gem kit SUBCOMMAND/)
    command.arguments.should.match(/deprecations/)
    command.description.should.match(/dated promise/)
  end
end
