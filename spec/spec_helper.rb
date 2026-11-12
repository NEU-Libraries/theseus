# frozen_string_literal: true

require "webmock/rspec"
require_relative "../lib/theseus"

# No spec may reach v1 production or a live Atlas.
WebMock.disable_net_connect!

module SpecHelpers
  # A JWT whose payload holds the given claims. The signature is junk; Theseus
  # never verifies it.
  def fake_jwt(claims)
    body = Base64.urlsafe_encode64(JSON.generate(claims), padding: false)
    "eyJhbGciOiJIUzI1NiJ9.#{body}.c2ln"
  end

  def fixture(name) = File.read(File.join(__dir__, "fixtures", name))
end

RSpec.configure do |config|
  config.include SpecHelpers
  config.disable_monkey_patching!
  config.order = :random
end
