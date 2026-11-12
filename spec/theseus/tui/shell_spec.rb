# frozen_string_literal: true

require "tmpdir"
require_relative "../../support_tui"

RSpec.describe Theseus::TUI do
  include TUISpecHelpers

  around { |example| Dir.mktmpdir { |dir| (@dir = dir) && example.run } }

  let(:out) { StringIO.new }
  let(:prompt) { TTY::Prompt::Test.new }
  let(:atlas) { FakeTUIAtlas.new }

  def tui(env = tui_env.merge("THESEUS_RUN_DIR" => @dir))
    described_class.new(config: Theseus::Config.new(env), out: out, prompt: prompt, atlas: atlas,
                        v1: FakeTUIV1.new, now: tui_now, tty: false, pastel: Pastel.new(enabled: false))
  end

  # Past the header: one pid, decline the plan, and quit.
  before do
    prompt.input << "neu:cf\nn\nn\n"
    prompt.input.rewind
  end

  it "draws the header from the pre-flight checks" do
    expect(tui.run).to eq(0)
    expect(out.string).to include("THESEUS · v1 → v2",
                                  "repository.library.northeastern.edu", "5h 41m left",
                                  "localhost:3001 · health ok", "Northeastern University")
  end

  it "shows a replay in place of the v1 host, and needs no token" do
    Dir.mktmpdir do |dir|
      env = tui_env("THESEUS_V1_REPLAY" => dir).except("V1_URL", "V1_JWT")
      expect(tui(env).run).to eq(0)
      expect(out.string).to include("replay: /", "not needed")
    end
  end

  it "refuses to start with less than 15 minutes on the v1 token" do
    env = tui_env("V1_JWT" => fake_jwt("exp" => Time.utc(2026, 11, 12, 9, 30).to_i))
    expect(tui(env).run).to eq(2)
    expect(out.string).to include("Theseus cannot start", "11 minutes left")
    expect(out.string).not_to include("THESEUS · v1 → v2")
  end

  it "names ATLAS_URL when Atlas does not answer" do
    atlas.unreachable = true
    expect(tui.run).to eq(2)
    expect(out.string).to include("Atlas at ATLAS_URL did not answer")
  end

  it "stops when Atlas holds nothing for neu:1" do
    atlas.root = nil
    expect(tui.run).to eq(2)
    expect(out.string).to include("Atlas holds nothing for neu:1", "Fix .env and start Theseus again.")
  end

  it "stops when neu:1 is not a Community" do
    atlas.root = { "id" => "w1", "type" => "Work" }
    expect(tui.run).to eq(2)
    expect(out.string).to include("not a Community")
  end
end
