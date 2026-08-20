# frozen_string_literal: true

require_relative "../../release"

module GemKit
  module Release
    # Raised instead of exiting, so the caller decides what a failure means:
    # the Thor CLI turns it into a non-zero status, and the specs assert on it.
    class Failure < StandardError; end

    module Commands
      # Shared base for the commands behind `gem kit`. Each is thin — ask a
      # library object a question, report — and knows nothing about Thor. The
      # work stays in Gate, VersionFile, Changelog and Deprecate; the parsing,
      # the help pages and the generator machinery stay in Thor.
      class Command
        RED   = "\e[0;31m"
        RESET = "\e[0m"

        attr_reader :options

        def initialize(options = {})
          @options = options
        end

        # The gem in the working directory. Everything is inferred from its
        # .gemspec, so there is nothing to configure in the common case.
        # `--gem` picks one out of a repository holding several.
        def project
          @project ||= Project.detect(Dir.pwd, name: options[:gem])
        rescue Project::NotFound, Project::Ambiguous => error
          fail_with(error.message)
        end

        def gate
          @gate ||= Gate.new(project)
        end

        def version_file
          VersionFile.new(project.version_file, template: project.version_template)
        end

        def say(message = "") = $stdout.puts(message)

        def fail_with(message)
          raise Failure, message
        end

        # Report a problem list under a heading and stop. One message — a
        # refusal is not half output and half diagnostics.
        def refuse(heading, problems)
          fail_with([heading, "", *problems.map { |problem| "  #{problem}" }].join("\n"))
        end

        def relative(path) = path.sub("#{project.root}/", "")

        def render(entries)
          lines(entries).each { |line| say("  #{line}") }
        end

        # Deprecation entries as display lines: the deadline, the rename, and
        # where it was declared.
        def lines(entries)
          entries.sort_by { |entry| [entry.removed_in, entry.name] }.flat_map do |entry|
            line = "#{entry.removed_in.to_s.ljust(8)} #{entry}"
            entry.declared_at ? [line, "#{" " * 8} #{entry.declared_at}"] : [line]
          end
        end
      end
    end
  end
end
