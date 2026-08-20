# frozen_string_literal: true

# RubyGems loads this file from every installed gem's lib/ on every `gem`
# invocation, which is how `gem kit` becomes a real command. Keep it to the
# require and the registration — anything heavier is a tax on `gem list`.

require "rubygems/command_manager"

require_relative "rubygems/commands/kit_command"

Gem::CommandManager.instance.register_command :kit
