# frozen_string_literal: true

require "tmpdir"
require "theseus/atlas_gateway"

RSpec.describe Theseus::Importer do
  around { |example| Dir.mktmpdir { |dir| (@dir = dir) && example.run } }

  def mods(handle = nil)
    id = handle ? %(<mods:identifier type="hdl">http://hdl.handle.net/#{handle}</mods:identifier>) : ""
    %(<mods:mods xmlns:mods="http://www.loc.gov/mods/v3"><mods:titleInfo/>#{id}</mods:mods>)
  end

  # v1: pid => [model, parent, mods]
  let(:records) do
    {
      "neu:1" => ["Community", nil, mods],
      "neu:466" => ["Community", "neu:1", mods],
      "neu:col" => ["Collection", "neu:466", mods("2047/C1")],
      "neu:cf" => ["CoreFile", "neu:col", mods("2047/D1")],
      "neu:cf2" => ["CoreFile", "neu:col", mods("2047/D2")]
    }
  end

  let(:v1) do
    recs = records
    Class.new do
      define_method(:solr_document) do |pid|
        model, parent, = recs.fetch(pid)
        { "id" => pid, "active_fedora_model_ssi" => model, "title_ssi" => pid,
          "parent_id_tesim" => parent && [parent] }.compact
      end
      define_method(:mods) { |pid| recs.fetch(pid)[2] }
    end.new
  end

  # A fake Atlas that records every call, keeps handles, and can fail on cue.
  let(:atlas) do
    Class.new do
      attr_reader :calls, :works
      attr_accessor :drop_handle, :fail_on

      def initialize = (@calls = []) && (@works = {}) && (@keys = {}) && (@next = 0)

      def create_community(parent) = container(:community, parent)
      def create_collection(parent) = container(:collection, parent)

      def create_work(parent, idempotency_key:, handle:)
        @calls << [:create_work, parent, handle]
        failure!(:create_work)
        noid = (@keys[idempotency_key] ||= "w#{@next += 1}")
        @works[noid] ||= { "id" => noid, "handle" => (drop_handle ? nil : handle) }
      end

      def put_mods(noid, path)
        @calls << [:put_mods, noid, File.basename(path)]
        failure!(:put_mods)
      end

      def complete(noid)
        @calls << [:complete, noid]
        failure!(:complete)
      end

      def find_work(noid) = @works.fetch(noid)

      private

        def container(type, parent)
          @calls << [type, parent]
          failure!(type)
          "c#{@next += 1}"
        end

        def failure!(step)
          raise Theseus::AtlasGateway::Failure, "Atlas answered 422: boom" if fail_on == step
        end
    end.new
  end

  let(:map) { Theseus::IdMap.new(File.join(@dir, "map.csv")) }
  let(:out) { StringIO.new }
  let(:importer) do
    described_class.new(v1: v1, atlas: atlas, map: map, mods_dir: File.join(@dir, "mods"),
                        root_noid: "root", out: out)
  end

  it "creates the missing ancestors top-down, then the Work, and maps each" do
    importer.run("neu:cf")

    expect(atlas.calls).to eq([
      [:community, "root"], [:put_mods, "c1", "neu_466.xml"],
      [:collection, "c1"], [:put_mods, "c2", "neu_col.xml"],
      [:create_work, "c2", "2047/D1"], [:put_mods, "w3", "neu_cf.xml"], [:complete, "w3"]
    ])
    expect(File.read(File.join(@dir, "map.csv"))).to eq(<<~CSV)
      pid,noid,object_type
      neu:1,root,community
      neu:466,c1,community
      neu:col,c2,collection
      neu:cf,w3,work
    CSV
    expect(File).to exist(File.join(@dir, "mods", "neu_cf.xml"))
  end

  it "creates only the Work for a sibling whose ancestors are mapped" do
    importer.run("neu:cf")
    atlas.calls.clear
    importer.run("neu:cf2")

    expect(atlas.calls.map(&:first)).to eq(%i[create_work put_mods complete])
    expect(atlas.calls.first[1]).to eq("c2")
  end

  it "refuses a pid already in the map without --force" do
    importer.run("neu:cf")
    expect { importer.run("neu:cf") }.to raise_error(Theseus::FindingError, /already_imported/)
  end

  it "replays the same Work with --force, with the same NOID" do
    importer.run("neu:cf")
    atlas.calls.clear
    importer.run("neu:cf", force: true)

    expect(atlas.calls.map(&:first)).to eq(%i[create_work put_mods complete])
    expect(map.noid_for("neu:cf")).to eq("w3")
  end

  it "refuses a CoreFile with no handle before any v2 write" do
    records["neu:cf"][2] = mods
    expect { importer.run("neu:cf") }.to raise_error(Theseus::FindingError, /neu:cf: missing_v1_handle/)
    expect(atlas.calls).to be_empty
  end

  it "makes no v2 write when any MODS in the chain is broken" do
    records["neu:466"][2] = "<mods:mods"
    expect { importer.run("neu:cf") }.to raise_error(Theseus::FindingError, /neu:466: invalid_mods/)
    expect(atlas.calls).to be_empty
  end

  it "does not complete a Work whose handle Atlas dropped" do
    atlas.drop_handle = true
    expect { importer.run("neu:cf") }.to raise_error(Theseus::AtlasError, /not 2047\/D1.*w3/m)
    expect(atlas.calls.map(&:first)).not_to include(:complete)
    expect(map.include?("neu:cf")).to be(false)
  end

  it "names the shell left behind when the MODS write fails" do
    atlas.fail_on = :put_mods
    expect { importer.run("neu:cf") }.to raise_error(Theseus::AtlasError) { |e|
      expect(e.noid).to eq("c1")
      expect(e.message).to include("neu:466", "c1", "remove it")
    }
    expect(map.include?("neu:466")).to be(false)
  end

  it "keeps the rows of ancestors created before a later failure" do
    atlas.fail_on = :create_work
    expect { importer.run("neu:cf") }.to raise_error(Theseus::AtlasError)
    expect(map.noid_for("neu:col")).to eq("c2")
    expect(map.include?("neu:cf")).to be(false)
  end

  it "creates only the pid under --into, walking nothing" do
    importer.run("neu:cf", into: "elsewhere")
    expect(atlas.calls.first).to eq([:create_work, "elsewhere", "2047/D1"])
    expect(map.include?("neu:col")).to be(false)
  end

  it "refuses a chain that ends at a top-level pid the map lacks" do
    records["neu:other"] = ["Community", nil, mods]
    records["neu:466"][1] = "neu:other"
    expect { importer.run("neu:cf") }.to raise_error(Theseus::FindingError, /unanchored.*neu:other/)
  end
end
