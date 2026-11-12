# frozen_string_literal: true

require "tmpdir"

RSpec.describe Theseus::IdMap do
  around { |example| Dir.mktmpdir { |dir| (@dir = dir) && example.run } }

  let(:path) { File.join(@dir, "runs", "map.csv") }

  it "writes the header once and a row per append, readable by a fresh load" do
    map = described_class.new(path)
    map.append("neu:1", "root", "community")
    map.append("neu:x", "w1", "work")

    expect(File.read(path)).to eq("pid,noid,object_type\nneu:1,root,community\nneu:x,w1,work\n")
    reloaded = described_class.new(path)
    expect(reloaded.noid_for("neu:x")).to eq("w1")
    expect(reloaded.type_for("neu:x")).to eq(:core_file)
  end

  it "lets the last row for a pid win" do
    map = described_class.new(path)
    map.append("neu:c", "first", "collection")
    map.append("neu:c", "second", "collection")
    expect(described_class.new(path).noid_for("neu:c")).to eq("second")
  end

  it "seeds neu:1 as the root once" do
    map = described_class.new(path)
    map.seed_root!("root")
    map.seed_root!("root")
    expect(File.readlines(path).size).to eq(2)
    expect(map.type_for("neu:1")).to eq(:community)
  end

  it "refuses a map whose root is not V2_ROOT (a map from before a reset)" do
    described_class.new(path).seed_root!("old")
    expect { described_class.new(path).seed_root!("new") }
      .to raise_error(Theseus::ConfigError, /start a new map/)
  end

  it "refuses an unknown object_type" do
    expect { described_class.new(path).append("neu:x", "n", "set") }.to raise_error(ArgumentError)
  end
end
