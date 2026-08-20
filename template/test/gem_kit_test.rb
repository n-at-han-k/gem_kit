# frozen_string_literal: true

require "test_helper"

class GemKitTest < Minitest::Test
  def test_version
    refute_nil GemKit::VERSION
  end
end
