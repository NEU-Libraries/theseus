# frozen_string_literal: true

require "tty/prompt/test"
require "theseus/tui"

# A fake Atlas for TUI specs: the gateway's read calls, with a root that
# holds neu:1. Writes are added by the specs that need them.
class FakeTUIAtlas
  attr_accessor :root, :health_status, :unreachable, :fail_on
  attr_reader :calls, :holders

  def initialize
    @root = { "id" => "d51c6hh", "type" => "Community", "tombstoned" => false }
    @health_status = "ok"
    @holders = {}
    @calls = []
    @next = 0
  end

  def health
    raise Theseus::AtlasGateway::Failure, "Faraday::ConnectionFailed: refused" if unreachable

    health_status
  end

  def find_by_legacy_pid(pid) = pid == "neu:1" ? root : holders[pid]
  def find_community(noid) = { "id" => noid, "title" => "Northeastern University" }

  def create_community(parent, legacy_pid:) = create(:community, parent, legacy_pid, "Community")
  def create_collection(parent, legacy_pid:) = create(:collection, parent, legacy_pid, "Collection")

  def create_work(parent, idempotency_key:, handle:, legacy_pid:)
    work = create(:create_work, parent, legacy_pid, "Work")
    @handles[work["id"]] = handle
    work.merge("handle" => handle)
  end

  def put_mods(noid, _path) = step(:put_mods, noid)
  def complete(noid) = step(:complete, noid)
  def find_work(noid) = { "id" => noid, "handle" => @handles.fetch(noid) }

  private

    def create(name, parent, pid, type)
      step(name, parent)
      noid = "n#{@next += 1}"
      holders[pid] = { "id" => noid, "type" => type, "tombstoned" => false }
      (@handles ||= {})[noid] = nil
      { "id" => noid, "legacy_pid" => pid }
    end

    def step(name, arg)
      calls << [name, arg]
      raise Theseus::AtlasGateway::Failure, "Atlas answered 422: boom" if fail_on == name
    end
end

# v1 for TUI specs: neu:cf, a CoreFile, in neu:col, in neu:466, in neu:1.
class FakeTUIV1
  MODS = %(<mods:mods xmlns:mods="http://www.loc.gov/mods/v3"><mods:titleInfo/>%s</mods:mods>)

  attr_reader :records

  def initialize
    @records = {
      "neu:466" => ["Community", "University Library", "neu:1", nil],
      "neu:col" => ["Collection", "Newspapers", "neu:466", "2047/C1"],
      "neu:cf" => ["CoreFile", "East Boston Community News", "neu:col", "2047/D1"],
      "neu:cf2" => ["CoreFile", "East Boston Community News, May", "neu:col", "2047/D2"]
    }
  end

  def solr_document(pid)
    model, title, parent, handle = records.fetch(pid) { raise Theseus::FindingError.new(pid, "v1_refused", "no such object") }
    { "id" => pid, "active_fedora_model_ssi" => model, "title_ssi" => title, "parent_id_tesim" => [parent],
      "identifier_tesim" => handle ? ["http://hdl.handle.net/#{handle}"] : [] }
  end

  def mods(pid)
    handle = records.fetch(pid)[3]
    format(MODS, handle ? %(<mods:identifier type="hdl">http://hdl.handle.net/#{handle}</mods:identifier>) : "")
  end
end

module TUISpecHelpers
  def tui_env(extra = {})
    { "V1_URL" => "https://repository.library.northeastern.edu",
      "V1_JWT" => fake_jwt("exp" => Time.utc(2026, 11, 12, 15).to_i),
      "ATLAS_URL" => "http://localhost:3001", "ATLAS_JWT" => "x" }.merge(extra)
  end

  def tui_now = -> { Time.utc(2026, 11, 12, 9, 19) }
end
