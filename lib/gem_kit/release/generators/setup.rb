# frozen_string_literal: true

require "thor"
require "thor/group"

require_relative "../commands/command"

module GemKit
  module Release
    module Generators
      # `gem kit setup` — a Thor generator, which is what Rails' own generators
      # are. Using one rather than hand-rolled File.write buys the whole
      # conflict protocol for free: `create`/`identical`/`conflict` status
      # lines, a prompt offering diff/overwrite/skip when a file exists and
      # differs, and --force / --skip / --pretend to answer that prompt ahead
      # of time.
      #
      # It writes the two documents that describe this toolchain, rendered for
      # the project's own name and versions. They are copies rather than links
      # because a policy nobody can read in their own repo is a policy nobody
      # follows, and because the examples are worth more with real numbers in
      # them.
      class Setup < Thor::Group
        include Thor::Actions

        # --force, --skip, --pretend and --quiet: Thor::Actions implements the
        # behaviour but leaves declaring the switches to the generator.
        add_runtime_options!

        class_option :gem, type: :string,
                           desc: "Which gem, in a repository holding more than one gemspec"

        def self.source_root
          File.expand_path("../templates", __dir__)
        end

        # Written into the project, not the working directory: `gem kit setup`
        # run from a subdirectory still belongs to the gem.
        def self.banner = "gem kit setup"

        def deprecations_document
          template("DEPRECATIONS.md.erb", File.join(project.root, "DEPRECATIONS.md"))
        end

        def release_document
          template("RELEASE.md.erb", File.join(project.root, "RELEASE.md"))
        end

        def where_to_link_them
          say ""
          say "Link them from your README and AGENTS.md so they are found."
        end

        # Everything below is machinery, not a step. Thor runs every public
        # method of a Thor::Group in order, so helpers have to say so.
        no_commands do
          # The values the templates render against. Kept small and obvious — a
          # template needing more than this is documenting the tool, not the
          # project.
          def name       = project.name
          def version    = project.version.to_s
          def next_major = project.next_major_version
          def changelog  = File.basename(project.changelog_path)
          def test       = project.test_command
          def today      = Time.now.strftime("%Y-%m-%d")

          def version_file
            project.version_file.sub("#{project.root}/", "")
          end

          def project
            @project ||= Project.detect(Dir.pwd, name: options[:gem])
          rescue Project::NotFound, Project::Ambiguous => error
            raise Failure, error.message
          end
        end
      end
    end
  end
end

__END__

describe "gem_kit/release/generators/setup" do
  require_relative "../../../../spec/support/gem_kit_release_spec"
  extend GemKitReleaseSpec

  it "writes both documents into the project root" do
    with_gem do |dir|
      status, out, _err = invoke(["setup"], dir)

      status.should == 0
      out.should.match(/create.*DEPRECATIONS\.md/)
      out.should.match(/create.*RELEASE\.md/)
      File.exist?(File.join(dir, "DEPRECATIONS.md")).should.be.true
      File.exist?(File.join(dir, "RELEASE.md")).should.be.true
    end
  end

  it "renders them for this project's name and versions" do
    with_gem(version: "4.1.0") do |dir|
      invoke(["setup"], dir)

      deprecations = File.read(File.join(dir, "DEPRECATIONS.md"))
      deprecations.should.match(/A deprecation in demo is a \*\*dated promise\*\*/)
      deprecations.should.match(/4\.1\.0, so the usual deadline is 5\.0/)
      deprecations.should.not.match(/<%=/)

      release = File.read(File.join(dir, "RELEASE.md"))
      release.should.match(/Releasing demo/)
      release.should.not.match(/<%=/)
    end
  end

  # Thor::Actions reports an unchanged file as `identical` rather than
  # rewriting it, which is the generator behaviour we switched to Thor for.
  it "reports an unchanged document as identical rather than rewriting it" do
    with_gem do |dir|
      invoke(["setup"], dir)
      before = File.mtime(File.join(dir, "RELEASE.md"))

      _status, out, _err = invoke(["setup"], dir)

      out.should.match(/identical.*RELEASE\.md/)
      File.mtime(File.join(dir, "RELEASE.md")).should == before
    end
  end

  it "--force overwrites a document that differs" do
    with_gem do |dir|
      File.write(File.join(dir, "RELEASE.md"), "mine\n")

      status, out, _err = invoke(["setup", "--force"], dir)

      status.should == 0
      out.should.match(/force.*RELEASE\.md/)
      File.read(File.join(dir, "RELEASE.md")).should.not == "mine\n"
    end
  end

  it "--skip leaves a document that differs alone" do
    with_gem do |dir|
      File.write(File.join(dir, "RELEASE.md"), "mine\n")

      invoke(["setup", "--skip"], dir).first.should == 0
      File.read(File.join(dir, "RELEASE.md")).should == "mine\n"
    end
  end

  it "--pretend writes nothing" do
    with_gem do |dir|
      invoke(["setup", "--pretend"], dir).first.should == 0
      File.exist?(File.join(dir, "RELEASE.md")).should.be.false
    end
  end

  it "is reachable by its alias" do
    with_gem do |dir|
      invoke(["init"], dir).first.should == 0
      File.exist?(File.join(dir, "RELEASE.md")).should.be.true
    end
  end

  it "reports a directory with no gemspec" do
    Dir.mktmpdir do |dir|
      invoke(["setup"], dir).first.should == 1
    end
  end
end
