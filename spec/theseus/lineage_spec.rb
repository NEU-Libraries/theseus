# frozen_string_literal: true

RSpec.describe Theseus::Lineage do
  # A fake v1 client over a hash of pid => Solr document.
  let(:docs) { {} }
  let(:client) do
    Class.new do
      attr_reader :calls

      def initialize(docs) = (@docs = docs) && (@calls = [])

      def solr_document(pid)
        @calls << pid
        @docs.fetch(pid) { raise Theseus::FindingError.new(pid, "v1_refused", "unavailable") }
      end
    end.new(docs)
  end

  def add(pid, model, parent = nil, title: pid)
    docs[pid] = { "id" => pid, "active_fedora_model_ssi" => model, "title_ssi" => title,
                  "parent_id_tesim" => parent && [parent] }.compact
  end

  # The real chain walked on 2026-11-12, shortened.
  before do
    add("neu:1", "Community")
    add("neu:466", "Community", "neu:1")
    add("neu:6002", "Collection", "neu:466")
    add("neu:rx918554d", "Collection", "neu:6002")
    add("neu:cj82kh734", "CoreFile", "neu:rx918554d")
  end

  it "walks to the top of the v1 tree when nothing is known" do
    chain = described_class.new(client).walk("neu:cj82kh734")

    expect(chain.objects.map(&:pid)).to eq(%w[neu:cj82kh734 neu:rx918554d neu:6002 neu:466 neu:1])
    expect(chain.top_down.first.pid).to eq("neu:1")
    expect(chain.anchor_pid).to be_nil
  end

  it "stops at the first known ancestor without fetching it" do
    known = { "neu:466" => :community }
    chain = described_class.new(client, known: known.method(:[])).walk("neu:cj82kh734")

    expect(chain.objects.map(&:pid)).to eq(%w[neu:cj82kh734 neu:rx918554d neu:6002])
    expect(chain.anchor_pid).to eq("neu:466")
    expect(client.calls).not_to include("neu:466")
  end

  it "walks nothing when the pid itself is known" do
    chain = described_class.new(client, known: { "neu:6002" => :collection }.method(:[])).walk("neu:6002")
    expect(chain.objects).to be_empty
  end

  it "refuses a CoreFile whose parent is a Community" do
    add("neu:bad", "CoreFile", "neu:466")
    expect { described_class.new(client).walk("neu:bad") }
      .to raise_error(Theseus::FindingError, /neu:bad: invalid_parent_type/)
  end

  it "checks the link to a known anchor too" do
    add("neu:bad", "CoreFile", "neu:466")
    known = { "neu:466" => :community }
    expect { described_class.new(client, known: known.method(:[])).walk("neu:bad") }
      .to raise_error(Theseus::FindingError, /invalid_parent_type/)
  end

  it "refuses a model outside phase 1" do
    add("neu:set", "Compilation", "neu:1")
    expect { described_class.new(client).walk("neu:set") }
      .to raise_error(Theseus::FindingError, /unsupported_model/)
  end

  it "refuses a cycle" do
    add("neu:a", "Collection", "neu:b")
    add("neu:b", "Collection", "neu:a")
    expect { described_class.new(client).walk("neu:a") }
      .to raise_error(Theseus::FindingError, /cyclic_ancestry/)
  end

  it "stops the whole walk when an ancestor is refused" do
    add("neu:orphan", "Collection", "neu:gone")
    expect { described_class.new(client).walk("neu:orphan") }
      .to raise_error(Theseus::FindingError, /neu:gone: v1_refused/)
  end
end
