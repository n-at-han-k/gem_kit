# frozen_string_literal: true

module GemKit
  module Release
    # The checks, in one place. Both the bump and the release ask the same two
    # questions of a target version, and neither should be hand-rolling them:
    #
    #   Is anything promised to disappear in this version still here?
    #   Does the changelog document this version?
    #
    # Every method returns a list of human-readable problems. Empty means pass,
    # which makes the callers trivial and lets CI use the same object.
    class Gate
      attr_reader :project

      def initialize(project)
        @project = project
      end

      # Deprecations whose deadline has arrived at `version`. This is the check
      # that has to run *before* a bump: bumping onto a deadline is what breaks
      # the promise, so the bump is the last moment anyone can be stopped.
      def deprecation_problems(version)
        project.load!

        GemKit::Deprecate.pending(version).map do |entry|
          "#{entry.removed_in.to_s.ljust(8)} #{entry}#{entry.declared_at ? "\n#{" " * 9}#{entry.declared_at}" : ""}"
        end
      end

      # Deprecations still inside their grace period — worth printing on the
      # way past, not worth blocking on.
      def upcoming_deprecations(version)
        project.load!
        GemKit::Deprecate.upcoming(version)
      end

      # Changelog format, plus "is there an entry for this version?" when one
      # is given. Without a version this is the format check alone, which is
      # the useful thing to run on every push.
      def changelog_problems(version = nil)
        changelog = Changelog.new(
          File.exist?(project.changelog_path) ? File.read(project.changelog_path) : nil,
          path: project.changelog_path,
        )

        version ? changelog.release_problems(version) : changelog.problems
      end

      # What is in the working tree but not in git. A gem built from an
      # uncommitted tree is a gem whose source exists nowhere — and `bump` and
      # `changelog --write` leave exactly two such files behind, which is
      # precisely the moment someone reaches for `release`.
      #
      # A directory that is not a git repository is not a problem: this gate
      # has nothing to say about it.
      def working_tree_problems
        return [] unless git?

        dirty = Dir.chdir(project.root) { `git status --porcelain`.lines.map(&:strip) }
        return [] if dirty.empty?

        ["#{dirty.size} uncommitted change(s) — the gem would match nothing in git:",
         *dirty.first(10).map { |line| "  #{line}" },
         *(dirty.size > 10 ? ["  … and #{dirty.size - 10} more"] : []),
         "",
         "The bump and the changelog belong in one commit. Or pass --allow-dirty."]
      end

      def git?
        Dir.chdir(project.root) { system("git rev-parse --git-dir >/dev/null 2>&1") }
      end

      # Everything standing between the project and releasing `version`.
      def release_problems(version = project.version, allow_dirty: false)
        problems = []

        changelog_problems(version).each { |problem| problems << problem }
        deprecation_problems(version).each do |problem|
          problems << "deprecation due in #{version}: #{problem}"
        end
        working_tree_problems.each { |problem| problems << problem } unless allow_dirty

        problems
      end

      # Everything standing between the project and *bumping to* `version`.
      # Only the deprecation deadline applies — the changelog for a version
      # cannot exist before the version does.
      def bump_problems(version)
        deprecation_problems(version).map { |problem| "deprecation due in #{version}: #{problem}" }
      end
    end
  end
end

__END__

describe "gem_kit/release/gate" do
  require "tmpdir"

  # A Project stub: the Gate only asks it for a changelog path and a version,
  # and to load the library (a no-op here — the specs drive the registry).
  stub_project = lambda do |changelog_path, version: "1.0.0", root: nil|
    Struct.new(:changelog_path, :version, :root) do
      def load! = true
    end.new(changelog_path, Gem::Version.new(version), root || File.dirname(changelog_path))
  end

  clean_changelog = <<~MD
    # Changelog

    ## [Unreleased]

    ## [1.0.0] - 2026-01-01

    ### Added

    - A thing.
  MD

  # Run a block with the deprecation registry isolated.
  isolated = lambda do |&block|
    saved = GemKit::Deprecate.registry.dup
    GemKit::Deprecate.registry.clear
    begin
      block.call
    ensure
      GemKit::Deprecate.registry.replace(saved)
    end
  end

  it "passes when the changelog documents the version and nothing is due" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "CHANGELOG.md")
      File.write(path, clean_changelog)

      isolated.call do
        GemKit::Release::Gate.new(stub_project.call(path)).release_problems("1.0.0").should == []
      end
    end
  end

  it "reports a missing changelog section for the version" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "CHANGELOG.md")
      File.write(path, clean_changelog)

      isolated.call do
        problems = GemKit::Release::Gate.new(stub_project.call(path)).release_problems("2.0.0")
        problems.first.should.match(/no section for 2\.0\.0/)
      end
    end
  end

  it "reports a deprecation whose deadline has arrived" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "CHANGELOG.md")
      File.write(path, clean_changelog)

      isolated.call do
        GemKit::Deprecate.register(name: "Old", replacement: "New", removed_in: "1.0")
        gate = GemKit::Release::Gate.new(stub_project.call(path))

        gate.release_problems("1.0.0").first.should.match(/deprecation due in 1\.0\.0: .*Old -> New/)
        gate.bump_problems("1.0.0").size.should == 1
      end
    end
  end

  it "does not block a bump on a deadline that has not arrived" do
    Dir.mktmpdir do |dir|
      isolated.call do
        GemKit::Deprecate.register(name: "Old", replacement: "New", removed_in: "2.0")
        gate = GemKit::Release::Gate.new(stub_project.call(File.join(dir, "CHANGELOG.md")))

        gate.bump_problems("1.1.0").should == []
        gate.upcoming_deprecations("1.1.0").map(&:name).should == ["Old"]
      end
    end
  end

  # The gate that catches what `bump` and `changelog --write` leave behind.
  it "reports an uncommitted working tree, and clears once it is committed" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "CHANGELOG.md"), clean_changelog)
      system("git init -q #{dir}")

      isolated.call do
        gate = GemKit::Release::Gate.new(stub_project.call(File.join(dir, "CHANGELOG.md"), root: dir))

        gate.release_problems("1.0.0").first.should.match(/uncommitted change/)
        gate.release_problems("1.0.0", allow_dirty: true).should == []

        system("git -C #{dir} add -A")
        system("git -C #{dir} -c user.name=t -c user.email=t@t commit -q -m x")
        gate.release_problems("1.0.0").should == []
      end
    end
  end

  it "says nothing about a directory that is not a git repository" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "CHANGELOG.md"), clean_changelog)

      isolated.call do
        GemKit::Release::Gate.new(stub_project.call(File.join(dir, "CHANGELOG.md"), root: dir))
          .working_tree_problems.should == []
      end
    end
  end

  it "checks changelog format alone when given no version" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "CHANGELOG.md")
      File.write(path, "## [1.0.0] - 2026-01-01\n\n### Added\n\n- x\n")

      isolated.call do
        GemKit::Release::Gate.new(stub_project.call(path)).changelog_problems
          .first.should.match(/must start with the title/)
      end
    end
  end

  it "reports a changelog that does not exist" do
    Dir.mktmpdir do |dir|
      isolated.call do
        GemKit::Release::Gate.new(stub_project.call(File.join(dir, "CHANGELOG.md")))
          .changelog_problems.first.should.match(/does not exist/)
      end
    end
  end
end
