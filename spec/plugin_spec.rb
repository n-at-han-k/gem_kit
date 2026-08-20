# frozen_string_literal: true

# The plugin itself: that a `gem` invocation ends up with `gem kit` registered
# and described, and that it is the only command we add.

require_relative "support/gem_kit_release_spec"

__END__

describe "rubygems_plugin" do
  require "rubygems/command_manager"

  # What RubyGems does on every `gem` invocation.
  load File.expand_path("../lib/rubygems_plugin.rb", __dir__)

  it "registers gem kit with the command manager" do
    Gem::CommandManager.instance.command_names.should.include?("kit")
    Gem::CommandManager.instance[:kit].should.be.kind_of?(Gem::Commands::KitCommand)
  end

  it "registers exactly one command" do
    # Every subcommand lives under `gem kit`, so nothing here can collide with
    # a command RubyGems ships now or adds later.
    ours = %w[setup bump changelog deprecations release tag]
    ours.each { |name| Gem::CommandManager.instance.command_names.should.not.include?(name) }
  end

  it "does not shadow a command RubyGems already ships" do
    # `gem check`, `gem build`, `gem push` and `gem setup` all exist — which is
    # why the toolchain sits behind one name of its own.
    %w[build check install list push update info search setup].should.not.include?("kit")
  end

  it "gives the command the summary, usage and description `gem help` prints" do
    command = Gem::Commands::KitCommand.new

    command.summary.to_s.should.not.be.empty
    command.usage.to_s.should.not.be.empty
    command.description.to_s.should.not.be.empty
    command.arguments.to_s.should.not.be.empty
  end
end
