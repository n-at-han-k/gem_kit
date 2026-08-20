# frozen_string_literal: true

require_relative "command"

module GemKit
  module Release
    module Commands
      # Without a version: everything outstanding. With one: only what comes
      # due there, failing if anything does — which is what makes it usable as
      # a CI gate.
      class Deprecations < Command



        def call(version = nil)
          project.load!
          registry = Deprecate.registry

          if registry.empty?
            say("No deprecations declared.")
            return
          end

          if version.nil?
            say("#{registry.size} outstanding deprecation(s) (current version #{project.version}):")
            return render(registry)
          end

          due = GemKit::Deprecate.pending(version)
          if due.empty?
            say("No deprecations come due at #{version}. (#{registry.size} outstanding overall.)")
            return
          end

          refuse("#{due.size} deprecation(s) come due at #{version} and must be removed first:", lines(due))
        end
      end
    end
  end
end

__END__

describe "gem_kit/release/commands/deprecations" do
  require_relative "../../../../spec/support/gem_kit_release_spec"
  extend GemKitReleaseSpec

  it "says so when nothing is declared" do
    with_gem do |dir|
      status, out, _err = invoke(["deprecations"], dir)
      status.should == 0
      out.should.match(/No deprecations declared/)
    end
  end

  it "lists everything outstanding with its deadline" do
    with_gem do |dir|
      status, out, _err = invoke(["deprecations"], dir,
                                 deprecations: [["Old", "New", "2.0"], ["Older", "Newer", "3.0"]])

      status.should == 0
      out.should.match(/2 outstanding deprecation\(s\) \(current version 1\.2\.3\)/)
      out.should.match(/2\.0\s+Old -> New/)
      out.should.match(/3\.0\s+Older -> Newer/)
    end
  end

  it "fails for a version with deprecations due, naming only those" do
    with_gem do |dir|
      status, _out, err = invoke(["deprecations", "2.0.0"], dir,
                                 deprecations: [["Old", "New", "2.0"], ["Later", "Newer", "3.0"]])

      status.should == 1
      err.should.match(/1 deprecation\(s\) come due at 2\.0\.0/)
      err.should.match(/Old -> New/)
      err.should.not.match(/Later/)
    end
  end

  it "passes for a version with nothing due, but says what remains" do
    with_gem do |dir|
      status, out, _err = invoke(["deprecations", "1.5.0"], dir, deprecations: [["Old", "New", "2.0"]])

      status.should == 0
      out.should.match(/No deprecations come due at 1\.5\.0\. \(1 outstanding overall\.\)/)
    end
  end

  it "is reachable by its alias" do
    with_gem do |dir|
      invoke(["deps"], dir).first.should == 0
    end
  end
end
