# frozen_string_literal: true

require_relative "command"

module GemKit
  module Release
    module Commands
      # The tag matters beyond bookkeeping: it is what the next changelog is
      # written against, so a missing one makes the following release harder to
      # describe.
      class Tag < Command



        def call
          tag = "#{options.fetch(:prefix, "v")}#{project.version}"

          Dir.chdir(project.root) do
            fail_with("not a git repository") unless system("git rev-parse --git-dir >/dev/null 2>&1")
            fail_with("tag #{tag} already exists") unless `git tag -l #{tag}`.strip.empty?
            fail_with("could not create tag #{tag}") unless system("git", "tag", "-a", tag, "-m", tag)

            say("Tagged #{tag}")

            if options[:push]
              fail_with("could not push #{tag}") unless system("git", "push", "origin", tag)
              say("Pushed #{tag}")
            else
              say("Push it with: git push origin #{tag}")
            end
          end
        end
      end
    end
  end
end

__END__

describe "gem_kit/release/commands/tag" do
  require_relative "../../../../spec/support/gem_kit_release_spec"
  extend GemKitReleaseSpec

  # git needs an identity and at least one commit before it will tag.
  as_repo = lambda do |dir|
    system("git init -q #{dir}")
    system("git -C #{dir} -c user.name=t -c user.email=t@t commit -q --allow-empty -m init")
  end

  it "tags the current version and says how to push it" do
    with_gem do |dir|
      as_repo.call(dir)

      status, out, _err = invoke(["tag"], dir)
      status.should == 0
      out.should.match(/Tagged v1\.2\.3/)
      out.should.match(/git push origin v1\.2\.3/)
      `git -C #{dir} tag -l`.strip.should == "v1.2.3"
    end
  end

  it "honours a custom prefix" do
    with_gem do |dir|
      as_repo.call(dir)

      invoke(["tag", "--prefix", "release-"], dir).first.should == 0
      `git -C #{dir} tag -l`.strip.should == "release-1.2.3"
    end
  end

  it "refuses to retag an existing version" do
    with_gem do |dir|
      as_repo.call(dir)
      invoke(["tag"], dir)

      status, _out, err = invoke(["tag"], dir)
      status.should == 1
      err.should.match(/tag v1\.2\.3 already exists/)
    end
  end

  it "reports a directory that is not a git repository" do
    with_gem do |dir|
      status, _out, err = invoke(["tag"], dir)
      status.should == 1
      err.should.match(/not a git repository/)
    end
  end
end
