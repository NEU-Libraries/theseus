# frozen_string_literal: true

RSpec.describe Theseus::CLI do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  def run(*argv, env: {}, tty: false)
    described_class.new(argv, out: out, err: err, env: env, tty: tty).run
  end

  it "prints usage instead of drawing the TUI into a pipe" do
    expect(run).to eq(1)
    expect(run("tui")).to eq(1)
    expect(err.string).to include("the TUI needs a terminal", "Usage:")
    expect(out.string).to be_empty
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
