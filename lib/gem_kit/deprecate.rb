# frozen_string_literal: true

require "rubygems/deprecate"

module GemKit
  # A deprecation is a dated promise: it names the replacement *and* the
  # version the old name stops existing in. Built on Gem::Deprecate, which
  # gets the message format and the skip_during escape hatch right, plus one
  # addition — a registry, so the set of outstanding promises is data the
  # release tooling can enforce rather than prose someone has to remember.
  #
  # Deprecate a method:
  #
  #   class Session
  #     extend GemKit::Deprecate
  #
  #     def old_reset = new_reset
  #     deprecate :old_reset, "Session#new_reset", "5.0"
  #   end
  #
  # Deprecate a whole constant that has moved or been renamed — leave the old
  # name in place as a subclass of the new one, then declare it:
  #
  #   class Completion < Brute::Completion::OpenRouter
  #     extend GemKit::Deprecate
  #     superseded_by "Brute::Completion::OpenRouter", "5.0"
  #   end
  #
  # Both warn on use, naming the caller. Gem::Deprecate.skip_during silences
  # them, so a test suite can exercise the old path in quiet.
  module Deprecate
    extend Gem::Deprecate

    # One outstanding deprecation. `removed_in` is the deadline the release
    # gate reads.
    Entry = Struct.new(:name, :replacement, :removed_in, :declared_at, keyword_init: true) do
      def to_s
        "#{name} -> #{replacement == :none ? "(no replacement)" : replacement}"
      end
    end

    class << self
      # Every deprecation declared in the loaded library, in declaration order.
      def registry
        @registry ||= []
      end

      def register(name:, replacement:, removed_in:, declared_at: nil)
        entry = Entry.new(
          name:        name.to_s,
          replacement: replacement,
          removed_in:  Gem::Version.new(removed_in.to_s),
          declared_at: declared_at || location(1),
        )
        registry << entry
        entry
      end

      # The deprecations that come due at `version` — every deadline that has
      # arrived or passed. Releasing `version` with any of these still in the
      # tree breaks the promise the warning made.
      def pending(version)
        target = Gem::Version.new(version.to_s)
        registry.select { |entry| entry.removed_in <= target }
      end

      # Deprecations still inside their grace period at `version`.
      def upcoming(version)
        target = Gem::Version.new(version.to_s)
        registry.reject { |entry| entry.removed_in <= target }
      end

      # Single funnel for every warning: Gem::Deprecate.skip_during works
      # across all of them, and specs have one place to listen.
      def warn(message)
        Kernel.warn(message) unless Gem::Deprecate.skip
      end

      # The Gem::Deprecate-shaped message. `origin` must be computed at the
      # call site — one frame deeper and it names this file rather than the
      # code that needs changing.
      def message(target, replacement, removed_in, origin)
        [
          "NOTE: #{target} is deprecated",
          replacement == :none ? " with no replacement" : "; use #{replacement} instead",
          ". It will be removed in #{removed_in}",
          "\n#{target} called from #{origin}.",
        ].join
      end

      def location(depth)
        caller_locations(depth + 1, 1)&.first&.then { |l| "#{l.path}:#{l.lineno}" }
      end
    end

    # Deprecate one method. Mirrors Gem::Deprecate#rubygems_deprecate, but the
    # deadline is explicit — a deprecation added late in a cycle usually wants
    # the major after next, and guessing that is not the tool's business.
    def deprecate(name, replacement, removed_in)
      label = singleton_class? ? "#{attached_object}.#{name}" : "#{self}##{name}"
      Deprecate.register(name: label, replacement: replacement, removed_in: removed_in,
                         declared_at: Deprecate.location(1))

      class_eval do
        old = "_deprecated_#{name}"
        alias_method old, name
        define_method name do |*args, &block|
          target = is_a?(Module) ? "#{self}.#{name}" : "#{self.class}##{name}"
          origin = Gem.location_of_caller.join(":")
          Deprecate.warn(Deprecate.message(target, replacement, removed_in, origin))
          send(old, *args, &block)
        end
        ruby2_keywords name if respond_to?(:ruby2_keywords, true)
      end
    end

    # Deprecate the constant this is called in — the renamed-or-moved case.
    # Named `superseded_by` rather than `deprecate_constant` because Module
    # already has a method by that name and shadowing it would be rude.
    def superseded_by(replacement, removed_in)
      Deprecate.register(name: name || to_s, replacement: replacement, removed_in: removed_in,
                         declared_at: Deprecate.location(1))

      return unless respond_to?(:new)

      define_singleton_method(:new) do |*args, **options, &block|
        origin = Gem.location_of_caller.join(":")
        Deprecate.warn(Deprecate.message(name || to_s, replacement, removed_in, origin))
        super(*args, **options, &block)
      end
    end
  end
end

__END__

describe "gem_kit/deprecate" do
  Deprecate = GemKit::Deprecate unless defined?(Deprecate)

  captured = []
  # Capture what Deprecate.warn emits and keep the shared registry clean —
  # these specs declare throwaway deprecations.
  isolated = lambda do |&block|
    saved    = Deprecate.registry.dup
    original = Deprecate.method(:warn)
    captured.clear
    Deprecate.define_singleton_method(:warn) { |message| captured << message }
    begin
      block.call
    ensure
      Deprecate.define_singleton_method(:warn, original)
      Deprecate.registry.replace(saved)
    end
  end

  it "warns on a deprecated method, naming replacement, version and caller" do
    isolated.call do
      klass = Class.new do
        extend Deprecate
        def new_name = :result
        def old_name = new_name
        deprecate :old_name, "Thing#new_name", "9.0"
      end

      klass.new.old_name.should == :result   # still works
      captured.size.should == 1
      captured.first.should.match(/is deprecated/)
      captured.first.should.match(/use Thing#new_name instead/)
      captured.first.should.match(/removed in 9\.0/)
      captured.first.should.match(/called from /)
    end
  end

  it "names the caller, not the deprecation machinery" do
    isolated.call do
      klass = Class.new do
        extend Deprecate
        def old_name = :result
        deprecate :old_name, "Thing#new_name", "9.0"
      end

      # These specs live in this file's __END__, so "the caller" is a line in
      # deprecate.rb either way — pin the exact line to tell them apart.
      klass.new.old_name; call_line = __LINE__
      captured.first.should.match(/called from .*deprecate\.rb:#{call_line}\./)
    end
  end

  it "labels a class-method deprecation by the class, not its singleton" do
    isolated.call do
      Class.new do
        def self.to_s = "Demo"
        def self.old_thing = :ok
        class << self
          extend Deprecate
          deprecate :old_thing, "Other.new_thing", "9.0"
        end
      end

      Deprecate.registry.last.name.should == "Demo.old_thing"
    end
  end

  it "warns on a superseded constant but keeps it working" do
    isolated.call do
      modern = Class.new { def initialize(x); @x = x; end; attr_reader :x }
      legacy = Class.new(modern) do
        extend Deprecate
        def self.name = "Old::Name"
        superseded_by "New::Name", "9.0"
      end

      legacy.new(42).x.should == 42          # still works
      captured.size.should == 1
      captured.first.should.match(/Old::Name is deprecated; use New::Name instead/)
    end
  end

  it "supports :none for a deprecation with no replacement" do
    isolated.call do
      klass = Class.new do
        extend Deprecate
        def gone = :ok
        deprecate :gone, :none, "9.0"
      end

      klass.new.gone
      captured.first.should.match(/with no replacement/)
    end
  end

  it "registers each declaration with its deadline and source" do
    isolated.call do
      Class.new do
        extend Deprecate
        def gone = nil
        deprecate :gone, "Other#kept", "9.0"
      end

      entry = Deprecate.registry.last
      entry.replacement.should == "Other#kept"
      entry.removed_in.should == Gem::Version.new("9.0")
      entry.declared_at.should.match(/deprecate\.rb:\d+/)
    end
  end

  it "splits the registry into pending and upcoming at a version" do
    isolated.call do
      Deprecate.registry.clear
      Deprecate.register(name: "A", replacement: "A2", removed_in: "5.0")
      Deprecate.register(name: "B", replacement: "B2", removed_in: "6.0")

      Deprecate.pending("5.0.0").map(&:name).should == ["A"]
      Deprecate.upcoming("5.0.0").map(&:name).should == ["B"]
      Deprecate.pending("4.9.0").should.be.empty
      Deprecate.pending("6.1.0").map(&:name).should == ["A", "B"]
    end
  end

  it "stays quiet inside Gem::Deprecate.skip_during" do
    saved = Deprecate.registry.dup
    begin
      klass = Class.new do
        extend Deprecate
        def quiet = :ok
        deprecate :quiet, "Other#loud", "9.0"
      end

      warned   = []
      original = Kernel.method(:warn)
      Kernel.define_singleton_method(:warn) { |*args| warned << args.join }
      begin
        Gem::Deprecate.skip_during { klass.new.quiet.should == :ok }
      ensure
        Kernel.define_singleton_method(:warn, original)
      end

      warned.should.be.empty
    ensure
      Deprecate.registry.replace(saved)
    end
  end
end
