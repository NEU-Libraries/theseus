# frozen_string_literal: true

require "tmpdir"

RSpec.describe "v1 recording and replay" do
  around { |example| Dir.mktmpdir { |dir| (@dir = dir) && example.run } }

  let(:doc) { { "id" => "neu:cf", "active_fedora_model_ssi" => "CoreFile", "parent_id_tesim" => ["neu:col"] } }
  let(:xml) { %(<mods:mods xmlns:mods="http://www.loc.gov/mods/v3"><mods:abstract>XM&lt;LGBT/&gt; é</mods:abstract></mods:mods>) }
  let(:live) do
    d = doc
    x = xml
    Class.new do
      define_method(:solr_document) { |_pid| d }
      define_method(:mods) { |_pid| x }
    end.new
  end

  it "replays what it recorded, as the same V1Object and MODS" do
    recorder = Theseus::V1Recorder.new(live, @dir)
    recorder.solr_document("neu:cf")
    recorder.mods("neu:cf")

    replay = Theseus::V1Replay.new(@dir)
    expect(Theseus::V1Object.from_solr(replay.solr_document("neu:cf")))
      .to eq(Theseus::V1Object.from_solr(doc))
    expect(replay.mods("neu:cf")).to eq(xml)
    expect(Dir.children(@dir)).to contain_exactly("neu_cf.solr.json", "neu_cf.mods.xml")
  end

  it "names the pid and the route a recording lacks" do
    expect { Theseus::V1Replay.new(@dir).mods("neu:none") }
      .to raise_error(Theseus::ConfigError, /no mods for neu:none \(neu_none.mods.xml\)/)
  end

  it "refuses a pid that is not a v1 pid, before it becomes a file name" do
    expect { Theseus::V1Replay.new(@dir).mods("../etc") }.to raise_error(Theseus::FindingError, /invalid_pid/)
  end

  it "refuses a replay folder that does not exist" do
    expect { Theseus::V1Replay.new(File.join(@dir, "nope")) }.to raise_error(Theseus::ConfigError, /not a folder/)
  end

  describe Theseus::Config do
    it "replays with no v1 token" do
      expect(described_class.new("THESEUS_V1_REPLAY" => @dir).v1_reader).to be_a(Theseus::V1Replay)
    end

    it "wraps live v1 in a recorder when asked to record" do
      env = { "V1_URL" => "https://v1.example", "V1_JWT" => fake_jwt("exp" => Time.now.to_i + 3600),
              "THESEUS_V1_RECORD" => @dir }
      expect(described_class.new(env).v1_reader).to be_a(Theseus::V1Recorder)
    end

    it "refuses to record and replay at once" do
      env = { "THESEUS_V1_REPLAY" => @dir, "THESEUS_V1_RECORD" => @dir }
      expect { described_class.new(env).v1_reader }.to raise_error(Theseus::ConfigError, /not both/)
    end
  end
end
