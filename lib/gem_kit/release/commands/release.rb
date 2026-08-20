# frozen_string_literal: true

require_relative "command"

module GemKit
  module Release
    module Commands
      # Gate, build, push, tag. The gates run before anything is built, because
      # a half-done release is worse than a refused one.
      class Release < Command



        def call
          version  = project.version.to_s
          problems = gate.release_problems(version, allow_dirty: options[:allow_dirty])

          refuse("Refusing to release #{project.name} #{version}:", problems) unless problems.empty?

          if options[:dry_run]
            say("#{project.name} #{version} is ready to release.")
            return
          end

          gemspec = File.basename(project.gemspec_path)
          package = "#{project.name}-#{version}.gem"

          Dir.chdir(project.root) do
            say("Building #{gemspec}…")
            fail_with("gem build failed") unless system("gem", "build", gemspec)

            say("Pushing #{package}…")
            fail_with("gem push failed") unless system("gem", "push", package)
          end

          say("Released #{project.name} #{version}")

          # Tagging is part of releasing, not a flag someone remembers. It runs
          # after the push rather than before, so a tag never points at a
          # version that failed to publish — and it pushes, because the gem is
          # public by now and a tag only this machine has is half a release.
          Tag.new(options.merge(push: true)).call unless options[:tag] == false
        end
      end
    end
  end
end

__END__

describe "gem_kit/release/commands/release" do
  require_relative "../../../../spec/support/gem_kit_release_spec"
  extend GemKitReleaseSpec

  it "--dry-run passes when the changelog documents the version" do
    with_gem do |dir|
      status, out, _err = invoke(["release", "--dry-run"], dir)
      status.should == 0
      out.should.match(/demo 1\.2\.3 is ready to release/)
    end
  end

  # A gem built from an uncommitted tree matches nothing in git.
  it "refuses while the working tree is dirty, before building anything" do
    with_gem do |dir|
      system("git init -q #{dir}")

      status, _out, err = invoke(["release"], dir)

      status.should == 1
      err.should.match(/uncommitted change/)
      err.should.match(/--allow-dirty/)
      Dir[File.join(dir, "*.gem")].should.be.empty
    end
  end

  it "--allow-dirty releases anyway" do
    with_gem do |dir|
      system("git init -q #{dir}")

      # --dry-run stops before the push, which is as far as a spec should go.
      invoke(["release", "--dry-run", "--allow-dirty"], dir).first.should == 0
    end
  end

  it "is satisfied once the tree is committed" do
    with_gem do |dir|
      system("git init -q #{dir}")
      system("git -C #{dir} add -A")
      system("git -C #{dir} -c user.name=t -c user.email=t@t commit -q -m x")

      invoke(["release", "--dry-run"], dir).first.should == 0
    end
  end

  it "refuses without a changelog entry, before building anything" do
    with_gem(changelog: :none) do |dir|
      status, _out, err = invoke(["release"], dir)

      status.should == 1
      err.should.match(/Refusing to release demo 1\.2\.3/)
      err.should.match(/does not exist/)
      Dir[File.join(dir, "*.gem")].should.be.empty
    end
  end

  it "refuses when a deprecation is due in this version, before building anything" do
    with_gem do |dir|
      status, _out, err = invoke(["release"], dir, deprecations: [["Old", "New", "1.0"]])

      status.should == 1
      err.should.match(/deprecation due in 1\.2\.3: .*Old -> New/)
      Dir[File.join(dir, "*.gem")].should.be.empty
    end
  end

  it "does not gate on a deprecation that is not yet due" do
    with_gem do |dir|
      invoke(["release", "--dry-run"], dir, deprecations: [["Old", "New", "9.0"]]).first.should == 0
    end
  end

  it "reports a directory with no gemspec" do
    Dir.mktmpdir do |dir|
      invoke(["release", "--dry-run"], dir).first.should == 1
    end
  end
end
