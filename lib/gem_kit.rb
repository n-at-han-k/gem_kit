# frozen_string_literal: true

require_relative "gem_kit/version"
require_relative "gem_kit/deprecate"

# The runtime half of the kit: what a library needs while it is *running*, as
# opposed to what its maintainer needs while releasing it.
#
# Right now that is one thing — GemKit::Deprecate, the deprecation DSL. It has
# no dependencies beyond RubyGems' own, deliberately: a library that deprecates
# a name should not thereby acquire a release toolchain.
#
#   class Session
#     extend GemKit::Deprecate
#
#     def old_reset = new_reset
#     deprecate :old_reset, "Session#new_reset", "5.0"
#   end
#
# The release half lives in the gem_kit-release gem, in this same repository:
# `gem kit bump|changelog|deprecations|release|tag`. It reads the registry this
# one populates, which is the whole point of the split — the promises are
# declared at runtime and enforced at release time, and only the enforcing end
# needs the tooling installed.
module GemKit
end
