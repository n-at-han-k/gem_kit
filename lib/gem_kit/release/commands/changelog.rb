# frozen_string_literal: true

require_relative "command"

module GemKit
  module Release
    module Commands
      # Linting is the default because it is the safe, read-only half. Writing
      # edits a file and costs money, so it asks for the flag.
      class Changelog < Command




        def call(version = nil)
          return write_entry if options[:write]

          problems = version ? gate.release_problems(version) : gate.changelog_problems

          if problems.empty?
            say("#{relative(project.changelog_path)} is #{version ? "ready to release #{version}" : "clean"}.")
            return
          end

          refuse("#{problems.size} problem(s) in #{relative(project.changelog_path)}:", problems)
        end

        private

          def write_entry
            writer = project.changelog_writer
            unless system("command -v #{writer} >/dev/null 2>&1")
              fail_with("#{writer} is not on PATH (set config.changelog_writer)")
            end

            say("Writing #{relative(project.changelog_path)} for #{project.version}…")
            fail_with("#{writer} failed") unless system(writer, prompt)
          end

          def prompt
            <<~PROMPT
              Update #{File.basename(project.changelog_path)} for the release of version #{project.version}.

              The changes to document are the commits since the last tag plus any
              uncommitted work. Read `git log`, `git status` and `git diff` first.

              Rules:
              - Follow Keep a Changelog (https://keepachangelog.com/en/1.1.0/) exactly.
                The file must pass `gem kit changelog #{project.version}`; run it when you
                are done and fix anything it reports.
              - Add one `## [#{project.version}] - #{Time.now.strftime("%Y-%m-%d")}` section
                directly below `## [Unreleased]`, and move anything already under
                [Unreleased] that shipped in this version into it. Leave [Unreleased] in
                place, empty.
              - Group entries only under: Added, Changed, Deprecated, Removed, Fixed,
                Security. Omit the groups with nothing in them.
              - Write for someone upgrading the gem: what changed in the public API, what
                they must now do differently. Name the constants and methods involved.
                Skip internal refactors, test-only changes and typo fixes.
              - Anything deprecated this cycle goes under Deprecated, naming the
                replacement and the version it will be removed in (see
                `gem kit deprecations`).
              - Match the voice and level of detail of the existing entries.
              - Edit #{File.basename(project.changelog_path)} only. Do not touch any other
                file, and do not commit.
            PROMPT
          end
      end
    end
  end
end

__END__

describe "gem_kit/release/commands/changelog" do
  require_relative "../../../../spec/support/gem_kit_release_spec"
  extend GemKitReleaseSpec

  it "lints the format when given no version" do
    with_gem do |dir|
      status, out, _err = invoke(["changelog"], dir)
      status.should == 0
      out.should.match(/CHANGELOG\.md is clean/)
    end
  end

  it "checks a version is ready to release" do
    with_gem do |dir|
      invoke(["changelog", "1.2.3"], dir).first.should == 0

      status, _out, err = invoke(["changelog", "9.9.9"], dir)
      status.should == 1
      err.should.match(/no section for 9\.9\.9/)
    end
  end

  it "reports a malformed changelog with line numbers" do
    with_gem(changelog: :none) do |dir|
      File.write(File.join(dir, "CHANGELOG.md"), "# Changelog\n\n## 1.0.0\n")

      status, _out, err = invoke(["changelog"], dir)
      status.should == 1
      err.should.match(/malformed version heading/)
      err.should.match(/CHANGELOG\.md:3/)
    end
  end

  it "reports a changelog that does not exist" do
    with_gem(changelog: :none) do |dir|
      status, _out, err = invoke(["changelog"], dir)
      status.should == 1
      err.should.match(/does not exist/)
    end
  end

  it "--write fails clearly when the configured writer is not on PATH" do
    with_gem do |dir|
      GemKit::Release.configure { |config| config.changelog_writer = "definitely-not-a-command" }
      begin
        status, _out, err = invoke(["changelog", "--write"], dir)
        status.should == 1
        err.should.match(/definitely-not-a-command is not on PATH/)
      ensure
        GemKit::Release.reset!
      end
    end
  end

  it "--write invokes the configured writer" do
    with_gem do |dir|
      # `true` accepts and ignores its argument, so this exercises the whole
      # path without spending anything.
      GemKit::Release.configure { |config| config.changelog_writer = "true" }
      begin
        status, out, _err = invoke(["changelog", "--write"], dir)
        status.should == 0
        out.should.match(/Writing CHANGELOG\.md for 1\.2\.3/)
      ensure
        GemKit::Release.reset!
      end
    end
  end

  it "is reachable by its alias" do
    with_gem do |dir|
      invoke(["log"], dir).first.should == 0
    end
  end
end
