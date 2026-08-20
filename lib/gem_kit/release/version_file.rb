# frozen_string_literal: true

require "erb"

module GemKit
  module Release
    # Owns the one file that states the version, and the semver arithmetic for
    # moving it. Two layouts are supported, and which one is in play is decided
    # by whether an ERB template sits beside the file:
    #
    #   lib/x/version.rb.erb present -> render it with `version` in scope
    #   otherwise                    -> substitute the version string in place
    #
    # The second is the common case and deliberately surgical: it rewrites the
    # quoted version literal and touches nothing else in the file.
    class VersionFile
      class Error < StandardError; end

      SEGMENTS = %w[major minor patch].freeze

      # A quoted semver literal, e.g. VERSION = "4.1.0"
      LITERAL = /(["'])(\d+\.\d+\.\d+(?:[-.][0-9A-Za-z.-]+)?)\1/

      attr_reader :path, :template

      def initialize(path, template: nil)
        @path     = path
        @template = template
      end

      # "4.1.0", :minor -> "4.2.0"
      def self.bump(version, segment)
        unless SEGMENTS.include?(segment.to_s)
          raise Error, "unknown segment #{segment.inspect} (expected #{SEGMENTS.join(", ")})"
        end

        major, minor, patch = version.to_s.split(".").map(&:to_i)
        case segment.to_s
        when "major" then "#{major + 1}.0.0"
        when "minor" then "#{major}.#{minor + 1}.0"
        when "patch" then "#{major}.#{minor}.#{patch + 1}"
        end
      end

      # The version currently written in the file.
      def read
        contents = File.read(path)
        match = contents.match(LITERAL)
        raise Error, "no version literal in #{path}" if match.nil?

        match[2]
      end

      # Write `version` into the file. Returns the version written.
      def write(version)
        if template
          File.write(path, ERB.new(File.read(template)).result(binding))
        else
          contents = File.read(path)
          raise Error, "no version literal in #{path}" unless contents.match?(LITERAL)

          File.write(path, contents.sub(LITERAL) { "#{$1}#{version}#{$1}" })
        end

        version
      end
    end
  end
end

__END__

describe "gem_kit/release/version_file" do
  require "tmpdir"

  VF = GemKit::Release::VersionFile unless defined?(VF)

  with_file = lambda do |contents, &block|
    Dir.mktmpdir do |dir|
      path = File.join(dir, "version.rb")
      File.write(path, contents)
      block.call(path, dir)
    end
  end

  it "bumps each segment, zeroing the ones below it" do
    VF.bump("4.1.3", :major).should == "5.0.0"
    VF.bump("4.1.3", :minor).should == "4.2.0"
    VF.bump("4.1.3", :patch).should == "4.1.4"
  end

  it "rejects an unknown segment" do
    lambda { VF.bump("1.0.0", :epoch) }.should.raise(GemKit::Release::VersionFile::Error)
  end

  it "reads the version literal out of the file" do
    with_file.call(%(module Demo\n  VERSION = "1.2.3"\nend\n)) do |path|
      VF.new(path).read.should == "1.2.3"
    end
  end

  it "rewrites only the version literal, leaving the rest of the file alone" do
    original = %(# frozen_string_literal: true\n\nmodule Demo\n  VERSION = "1.2.3" # keep\nend\n)
    with_file.call(original) do |path|
      VF.new(path).write("2.0.0").should == "2.0.0"
      File.read(path).should == original.sub("1.2.3", "2.0.0")
    end
  end

  it "handles single-quoted literals" do
    with_file.call(%(VERSION = '0.9.0'\n)) do |path|
      VF.new(path).write("0.10.0")
      File.read(path).should == %(VERSION = '0.10.0'\n)
    end
  end

  it "raises when there is no version literal to rewrite" do
    with_file.call("module Demo\nend\n") do |path|
      lambda { VF.new(path).read }.should.raise(GemKit::Release::VersionFile::Error)
      lambda { VF.new(path).write("1.0.0") }.should.raise(GemKit::Release::VersionFile::Error)
    end
  end

  it "renders an ERB template when the project generates its version file" do
    with_file.call(%(VERSION = "0.0.0"\n)) do |path, dir|
      template = File.join(dir, "version.rb.erb")
      File.write(template, %(module Demo\n  VERSION = "<%= version %>"\nend\n))

      VF.new(path, template: template).write("3.1.4")
      File.read(path).should == %(module Demo\n  VERSION = "3.1.4"\nend\n)
    end
  end
end
