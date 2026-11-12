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
      .to raise_error(Theseus::ConfigError, "Set ATLAS_URL, ATLAS_JWT (see .env.example).")
  end

  it "keeps runs in runs/ unless THESEUS_RUN_DIR says otherwise" do
    expect(described_class.new({}).run_dir).to eq("runs")
    expect(described_class.new("THESEUS_RUN_DIR" => "rehearsal").run_dir).to eq("rehearsal")
  end

  it "names the variables it no longer reads" do
    env = { "V2_ROOT" => "qz614p7", "THESEUS_MAP" => " " }
    expect(described_class.new(env).obsolete_vars).to eq(["V2_ROOT"])
  end
end
