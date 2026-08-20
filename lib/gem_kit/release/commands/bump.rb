# frozen_string_literal: true

require_relative "command"

module GemKit
  module Release
    module Commands
      # The deadline check lives here rather than at release time because the
      # bump is the last moment anyone can be stopped: once the version file
      # says 5.0.0, every promise to disappear "in 5.0" is already broken.
      class Bump < Command




        def call(segment = "patch")
          current = project.version.to_s

          begin
            target = VersionFile.bump(current, segment)
          rescue VersionFile::Error => error
            fail_with(error.message)
          end

          problems = gate.bump_problems(target)
          unless problems.empty?
            unless options[:force]
              refuse("Refusing to bump #{current} -> #{target}:",
                     problems + ["", "Remove them, then bump. Override with --force."])
            end

            say("--force given; bumping past #{problems.size} deprecation(s) anyway.")
          end

          version_file.write(target)
          say("#{current} -> #{target}")

          upcoming = gate.upcoming_deprecations(target)
          unless upcoming.empty?
            say("#{upcoming.size} deprecation(s) still outstanding (none due in #{target}).")
          end

          # The changelog is the one release artefact nothing regenerates, and
          # the one most easily forgotten — so say so loudly.
          say
          say("#{RED}now run: gem kit changelog --write#{RESET}")
        end
      end
    end
  end
end

__END__

describe "gem_kit/release/commands/bump" do
  require_relative "../../../../spec/support/gem_kit_release_spec"
  extend GemKitReleaseSpec

  it "moves the version and points at the changelog" do
    with_gem do |dir|
      status, out, _err = invoke(["bump", "minor"], dir)

      status.should == 0
      out.should.match(/1\.2\.3 -> 1\.3\.0/)
      out.should.match(/now run: gem kit changelog --write/)
      File.read(File.join(dir, "lib/demo/version.rb")).should.match(/"1\.3\.0"/)
    end
  end

  it "defaults to a patch bump" do
    with_gem do |dir|
      invoke(["bump"], dir)
      File.read(File.join(dir, "lib/demo/version.rb")).should.match(/"1\.2\.4"/)
    end
  end

  it "refuses to bump onto a deadline, leaving the version file alone" do
    with_gem do |dir|
      status, _out, err = invoke(["bump", "major"], dir, deprecations: [["Old", "New", "2.0"]])

      status.should == 1
      err.should.match(/Refusing to bump 1\.2\.3 -> 2\.0\.0/)
      err.should.match(/Old -> New/)
      File.read(File.join(dir, "lib/demo/version.rb")).should.match(/"1\.2\.3"/)
    end
  end

  it "--force bumps past a deadline and says so" do
    with_gem do |dir|
      status, out, _err = invoke(["bump", "major", "--force"], dir, deprecations: [["Old", "New", "2.0"]])

      status.should == 0
      out.should.match(/--force given; bumping past 1 deprecation/)
      File.read(File.join(dir, "lib/demo/version.rb")).should.match(/"2\.0\.0"/)
    end
  end

  it "mentions deprecations outstanding but not yet due" do
    with_gem do |dir|
      _status, out, _err = invoke(["bump", "minor"], dir, deprecations: [["Old", "New", "9.0"]])
      out.should.match(/1 deprecation\(s\) still outstanding \(none due in 1\.3\.0\)/)
    end
  end

  it "rejects a segment that is not major, minor or patch" do
    with_gem do |dir|
      status, _out, _err = invoke(["bump", "epoch"], dir)
      status.should.not == 0
      File.read(File.join(dir, "lib/demo/version.rb")).should.match(/"1\.2\.3"/)
    end
  end

  it "reports a directory with no gemspec" do
    Dir.mktmpdir do |dir|
      status, _out, err = invoke(["bump", "minor"], dir)
      status.should == 1
      err.should.match(/no \.gemspec/)
    end
  end
end
