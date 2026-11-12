# frozen_string_literal: true

require "tty/prompt/test"
require "theseus/tui"

# A fake Atlas for TUI specs: the gateway's read calls, with a root that
# holds neu:1. Writes are added by the specs that need them.
class FakeTUIAtlas
  attr_accessor :root, :health_status, :unreachable

  def initialize
    @root = { "id" => "d51c6hh", "type" => "Community", "tombstoned" => false }
    @health_status = "ok"
  end

  def health
    raise Theseus::AtlasGateway::Failure, "Faraday::ConnectionFailed: refused" if unreachable

    health_status
  end

  def find_by_legacy_pid(pid) = pid == "neu:1" ? root : nil
  def find_community(noid) = { "id" => noid, "title" => "Northeastern University" }
end

module TUISpecHelpers
  def tui_env(extra = {})
    { "V1_URL" => "https://repository.library.northeastern.edu",
      "V1_JWT" => fake_jwt("exp" => Time.utc(2026, 11, 12, 15).to_i),
      "ATLAS_URL" => "http://localhost:3001", "ATLAS_JWT" => "x" }.merge(extra)
  end

  def tui_now = -> { Time.utc(2026, 11, 12, 9, 19) }
end
