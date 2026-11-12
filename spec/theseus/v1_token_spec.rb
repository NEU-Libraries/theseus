# frozen_string_literal: true

RSpec.describe Theseus::V1Token do
  let(:now) { Time.at(1_700_000_000) }

  it "passes a token that has not expired" do
    token = described_class.new(fake_jwt("user_id" => 1, "exp" => now.to_i + 60), now: -> { now })
    expect(token.check!).to eq(token)
  end

  it "refuses an expired token before any call to v1" do
    token = described_class.new(fake_jwt("user_id" => 1, "exp" => now.to_i - 1), now: -> { now })
    expect { token.check! }.to raise_error(Theseus::ConfigError, /expired/)
  end

  it "refuses a value that is not a JWT" do
    expect { described_class.new("not-a-token").check! }.to raise_error(Theseus::ConfigError, /not a JWT/)
  end

  it "refuses a token with no exp claim" do
    expect { described_class.new(fake_jwt("user_id" => 1)).check! }.to raise_error(Theseus::ConfigError, /exp/)
  end
end
