# frozen_string_literal: true

require "tmpdir"

RSpec.describe Theseus::RunLog do
  around { |example| Dir.mktmpdir { |dir| (@dir = dir) && example.run } }

  let(:log) { described_class.new(File.join(@dir, "runs"), clock: -> { Time.utc(2026, 11, 12, 9, 30) }) }

  it "writes the header once and a row per append" do
    log.append("neu:466", "c1", "community", "created")
    log.append("neu:x", "w1", "work", "replayed")

    expect(File.read(log.path)).to eq(<<~CSV)
      at,pid,noid,object_type,outcome
      2026-11-12T09:30:00Z,neu:466,c1,community,created
      2026-11-12T09:30:00Z,neu:x,w1,work,replayed
    CSV
  end

  it "adds to an existing log without a second header" do
    log.append("neu:466", "c1", "community", "created")
    described_class.new(File.join(@dir, "runs")).append("neu:col", "c2", "collection", "adopted")
    expect(File.readlines(log.path).grep(/^at,/).size).to eq(1)
  end

  it "refuses an unknown object_type or outcome" do
    expect { log.append("neu:x", "n", "set", "created") }.to raise_error(ArgumentError)
    expect { log.append("neu:x", "n", "work", "mapped") }.to raise_error(ArgumentError)
  end
end
