# frozen_string_literal: true

RSpec.describe Theseus::CLI do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def run(*argv, env: {})
    described_class.new(argv, out: out, err: err, env: env).run
  end

  it "prints usage and exits 1 for an unknown command" do
    expect(run("frobnicate", "neu:1")).to eq(1)
    expect(err.string).to include("Usage:")
  end

  it "exits 1 when the pid is missing" do
    expect(run("lookup")).to eq(1)
  end

  it "exits 1 for an unknown option" do
    expect(run("import", "neu:1", "--bogus")).to eq(1)
  end
end
