# frozen_string_literal: true

RSpec.describe Theseus::Config do
  it "names every missing v1 variable" do
    expect { described_class.new({}).require_v1! }
      .to raise_error(Theseus::ConfigError, /V1_URL, V1_JWT/)
  end

  it "treats a blank variable as missing" do
    env = { "V1_URL" => "https://v1.example", "V1_JWT" => "  " }
    expect { described_class.new(env).require_v1! }.to raise_error(Theseus::ConfigError, /V1_JWT/)
  end

  it "checks the v1 token's expiry" do
    env = { "V1_URL" => "https://v1.example", "V1_JWT" => fake_jwt("exp" => 1) }
    expect { described_class.new(env).require_v1! }.to raise_error(Theseus::ConfigError, /expired/)
  end

  it "names every missing v2 variable" do
    expect { described_class.new({}).require_v2! }
      .to raise_error(Theseus::ConfigError, /ATLAS_URL, ATLAS_JWT, V2_ROOT, THESEUS_MAP/)
  end
end
