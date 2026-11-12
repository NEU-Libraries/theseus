# frozen_string_literal: true

require "csv"
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

  # A fake Atlas that records every write, holds each pid once, keeps
  # handles, and can fail on cue. It starts with the root holding neu:1.
  let(:atlas) do
    Class.new do
      attr_reader :calls, :works, :holders
      attr_accessor :drop_handle, :drop_pid, :fail_on, :hide_from_lookup

      def initialize
        @calls = []
        @works = {}
        @keys = {}
        @next = 0
        @holders = { "neu:1" => { "id" => "root", "type" => "Community", "tombstoned" => false } }
        @hide_from_lookup = []
      end

      def create_community(parent, legacy_pid:) = container(:community, parent, legacy_pid)
      def create_collection(parent, legacy_pid:) = container(:collection, parent, legacy_pid)

      def create_work(parent, idempotency_key:, handle:, legacy_pid:)
        @calls << [:create_work, parent, handle]
        failure!(:create_work)
        noid = (@keys[idempotency_key] ||= "w#{@next += 1}")
        hold(legacy_pid, noid, "Work")
        @works[noid] ||= { "id" => noid, "handle" => (drop_handle ? nil : handle),
                           "legacy_pid" => (drop_pid ? nil : legacy_pid) }
      end

      # A pid in hide_from_lookup is missed once, as by a walk that ran before
      # a crashed run's create landed.
      def find_by_legacy_pid(pid) = hide_from_lookup.delete(pid) ? nil : @holders[pid]

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

        def container(type, parent, legacy_pid)
          @calls << [type, parent]
          failure!(type)
          if (held = @holders[legacy_pid])
            raise Theseus::AtlasGateway::PidTaken.new("Atlas answered 409", held["id"])
          end

          noid = "c#{@next += 1}"
          hold(legacy_pid, noid, type.to_s.capitalize)
          { "id" => noid, "legacy_pid" => (drop_pid ? nil : legacy_pid) }
        end

        def hold(pid, noid, type)
          @holders[pid] ||= { "id" => noid, "type" => type, "tombstoned" => false } unless drop_pid
        end

        def failure!(step)
          raise Theseus::AtlasGateway::Failure, "Atlas answered 422: boom" if fail_on == step
        end
    end.new
  end

  let(:log) { Theseus::RunLog.new(File.join(@dir, "runs")) }
  let(:out) { StringIO.new }
  let(:importer) do
    described_class.new(v1: v1, atlas: atlas, log: log, mods_dir: File.join(@dir, "runs", "mods"), out: out)
  end

  def logged = File.exist?(log.path) ? CSV.read(log.path, headers: true).map { |r| r.to_h.except("at") } : []

  it "creates the missing ancestors top-down under the root Atlas holds for neu:1" do
    importer.run("neu:cf")

    expect(atlas.calls).to eq([
      [:community, "root"], [:put_mods, "c1", "neu_466.xml"],
      [:collection, "c1"], [:put_mods, "c2", "neu_col.xml"],
      [:create_work, "c2", "2047/D1"], [:put_mods, "w3", "neu_cf.xml"], [:complete, "w3"]
    ])
    expect(atlas.holders.transform_values { |h| h["id"] })
      .to eq("neu:1" => "root", "neu:466" => "c1", "neu:col" => "c2", "neu:cf" => "w3")
    expect(logged.map { |r| r.values_at("pid", "noid", "object_type", "outcome") }).to eq([
      %w[neu:466 c1 community created], %w[neu:col c2 collection created], %w[neu:cf w3 work created]
    ])
    expect(File).to exist(File.join(@dir, "runs", "mods", "neu_cf.xml"))
  end

  it "creates only the Work for a sibling whose Collection Atlas holds" do
    importer.run("neu:cf")
    atlas.calls.clear
    importer.run("neu:cf2")

    expect(atlas.calls.map(&:first)).to eq(%i[create_work put_mods complete])
    expect(atlas.calls.first[1]).to eq("c2")
  end

  it "starts from what Atlas holds, with no log from earlier runs" do
    importer.run("neu:cf")
    FileUtils.rm_rf(File.join(@dir, "runs"))
    atlas.calls.clear
    importer.run("neu:cf2")

    expect(atlas.calls.first).to eq([:create_work, "c2", "2047/D2"])
  end

  it "refuses a pid Atlas already holds without --force" do
    importer.run("neu:cf")
    expect { importer.run("neu:cf") }.to raise_error(Theseus::FindingError, /already_imported: Atlas has it as w3/)
  end

  it "replays the same Work with --force, with the same NOID" do
    importer.run("neu:cf")
    atlas.calls.clear
    importer.run("neu:cf", force: true)

    expect(atlas.calls.map(&:first)).to eq(%i[create_work put_mods complete])
    expect(logged.last).to include("pid" => "neu:cf", "noid" => "w3", "outcome" => "replayed")
  end

  it "adopts the container Atlas names when its pid is taken" do
    importer.run("neu:cf")
    atlas.calls.clear
    importer.run("neu:col", force: true)

    expect(atlas.calls).to eq([[:collection, "c1"], [:put_mods, "c2", "neu_col.xml"]])
    expect(logged.last).to include("pid" => "neu:col", "noid" => "c2", "outcome" => "adopted")
    expect(out.string).to include("neu:col -> c2 (collection) neu:col [adopted]")
  end

  it "adopts a container a crashed run created but the walk missed" do
    importer.run("neu:cf")
    atlas.hide_from_lookup = ["neu:col"]
    atlas.calls.clear
    importer.run("neu:cf2")

    expect(atlas.calls.map(&:first)).to eq(%i[collection put_mods create_work put_mods complete])
    expect(atlas.calls[2]).to eq([:create_work, "c2", "2047/D2"])
  end

  it "picks up after a crash without creating the finished ancestors again" do
    atlas.fail_on = :collection
    expect { importer.run("neu:cf") }.to raise_error(Theseus::AtlasError)
    atlas.fail_on = nil
    atlas.calls.clear
    importer.run("neu:cf")

    expect(atlas.calls.first).to eq([:collection, "c1"])
    expect(atlas.calls.map(&:first)).not_to include(:community)
  end

  it "stops with a configuration error when Atlas holds nothing for neu:1" do
    atlas.holders.delete("neu:1")
    expect { importer.run("neu:cf") }.to raise_error(Theseus::ConfigError, /holds nothing for neu:1/)
    expect(atlas.calls).to be_empty
  end

  it "refuses to build under a tombstoned ancestor" do
    importer.run("neu:cf")
    atlas.holders["neu:col"]["tombstoned"] = true
    atlas.calls.clear
    expect { importer.run("neu:cf2") }.to raise_error(Theseus::FindingError, /neu:col: tombstoned_in_v2.*c2/)
    expect(atlas.calls).to be_empty
  end

  it "stops at the first create when Atlas drops the pid" do
    atlas.drop_pid = true
    expect { importer.run("neu:cf") }.to raise_error(Theseus::AtlasError) { |e|
      expect(e.noid).to eq("c1")
      expect(e.message).to include("neu:466", "older than 0.6.279")
    }
    expect(atlas.calls).to eq([[:community, "root"]])
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
    expect(logged.map { |r| r["pid"] }).not_to include("neu:cf")
  end

  it "names the shell left behind when the MODS write fails" do
    atlas.fail_on = :put_mods
    expect { importer.run("neu:cf") }.to raise_error(Theseus::AtlasError) { |e|
      expect(e.noid).to eq("c1")
      expect(e.message).to include("neu:466", "c1", "remove it")
    }
  end

  it "creates only the pid under --into, walking nothing" do
    importer.run("neu:cf", into: "elsewhere")
    expect(atlas.calls.first).to eq([:create_work, "elsewhere", "2047/D1"])
    expect(atlas.holders).not_to include("neu:col")
  end

  it "refuses a chain that ends at a top-level pid Atlas lacks" do
    records["neu:other"] = ["Community", nil, mods]
    records["neu:466"][1] = "neu:other"
    expect { importer.run("neu:cf") }.to raise_error(Theseus::FindingError, /unanchored.*neu:other/)
  end
end
