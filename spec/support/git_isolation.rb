# frozen_string_literal: true

# Tests build throwaway projects under Dir.tmpdir and then ask whether they are
# git repositories. Git answers by walking UP from the directory until it finds
# a .git or runs out of parents — so the answer depends on whether anything
# ABOVE the temp root happens to be a repository. A stray `git init` in /tmp
# (or a home directory that is itself a repo, on a machine whose TMPDIR lives
# there) turns every "not a repository" test into a failure that reports that
# repository's untracked files.
#
# The gate is right to walk up: a gem in a monorepo subdirectory legitimately
# has its repository root above it, so narrowing production behaviour would
# break that. It is the TESTS that must guarantee their own isolation.
#
# GIT_CEILING_DIRECTORIES stops the walk. Git will not ascend into any
# directory listed, so a temp project can only ever find a repository the test
# itself created. Realpath because git compares resolved paths and /tmp is a
# symlink on some systems; any existing value is preserved rather than clobbered.
#
# Set once, process-wide, because no test should ever see a repository it did
# not make.
require "tmpdir"

ENV["GIT_CEILING_DIRECTORIES"] = [
  File.realpath(Dir.tmpdir),
  ENV["GIT_CEILING_DIRECTORIES"],
].compact.reject(&:empty?).join(":")
