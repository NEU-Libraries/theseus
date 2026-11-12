# frozen_string_literal: true

require "tmpdir"
require_relative "../../support_tui"

RSpec.describe Theseus::TUI, "the guided run" do
  include TUISpecHelpers

  around { |example| Dir.mktmpdir { |dir| (@dir = dir) && example.run } }

  let(:out) { StringIO.new }
  let(:prompt) { TTY::Prompt::Test.new }
  let(:atlas) { FakeTUIAtlas.new }
  let(:v1) { FakeTUIV1.new }
  let(:tui) do
    described_class.new(config: Theseus::Config.new(tui_env("THESEUS_RUN_DIR" => @dir)), out: out,
                        prompt: prompt, atlas: atlas, v1: v1, now: tui_now, tty: false,
                        pastel: Pastel.new(enabled: false))
  end

  def answer(*lines)
    prompt.input << lines.map { |line| "#{line}\n" }.join
    prompt.input.rewind
  end

  it "traces, checks, plans, creates and sums up one pid" do
    answer("neu:cf", "y", "n")
    expect(tui.run).to eq(0)

    text = out.string
    expect(text).to include(
      "1  Trace the v1 ancestry  read-only · one request a second",
      "✔ neu:cf         Work       East Boston Community News     hdl 2047/D1",
      "✔ neu:466        Community  University Library",
      "● neu:1          already in v2 · d51c6hh",
      "✔ MODS             3 records · fetched · well-formed · saved as evidence",
      "✔ Handle           2047/D1, from the CoreFile's MODS",
      "3  The plan  create 3 objects under d51c6hh, top-down",
      "Phase 1 copies no permissions",
      "4  Create in v2",
      "✔ Community  University Library                   n1",
      "✔ Work       East Boston Community News           n3 · completed",
      "2047/D1 · kept, nothing minted",
      "✔ migrated",
      "http://localhost:3000/works/n3",
      "/files/neu:cf  →  /works/n3  (redirects now)",
      "https://hdl.handle.net/2047/D1  (unchanged)",
      "3 objects created"
    )
    expect(text.index("│ neu:466 │")).to be < text.index("│ neu:col │") # the plan table, top-down
    expect(atlas.holders.keys).to eq(%w[neu:466 neu:col neu:cf])
  end

  it "creates nothing when the presenter declines the plan" do
    answer("neu:cf", "n", "n")
    expect(tui.run).to eq(0)
    expect(atlas.calls).to be_empty
    expect(out.string).not_to include("4  Create in v2")
  end

  it "goes round again for another pid, creating only the sibling Work" do
    answer("neu:cf", "y", "y", "neu:cf2", "y", "n")
    expect(tui.run).to eq(0)

    expect(out.string).to include("● neu:col        already in v2 · n2", "1 object created")
    expect(atlas.calls.last(3).map(&:first)).to eq(%i[create_work put_mods complete])
  end

  context "with demo pids" do
    let(:tui) do
      path = File.join(@dir, "demo_pids.yml")
      File.write(path, "- pid: neu:cf\n  note: the whole chain\n- pid: neu:cf2\n  note: a sibling\n")
      env = tui_env("THESEUS_RUN_DIR" => @dir, "THESEUS_DEMO_PIDS" => path)
      described_class.new(config: Theseus::Config.new(env), out: out, prompt: prompt, atlas: atlas, v1: v1,
                          now: tui_now, tty: false, pastel: Pastel.new(enabled: false))
    end

    it "offers them, with their notes, and migrates the one picked" do
      answer("", "y", "n") # Enter picks the first
      expect(tui.run).to eq(0)

      expect(prompt.output.string).to include("neu:cf          the whole chain", "Another pid…")
      expect(atlas.holders.keys).to include("neu:cf")
    end

    it "lets the presenter type any other pid" do
      down = "\e[B"
      answer("#{down}#{down}", "neu:cf2", "y", "n")
      expect(tui.run).to eq(0)
      expect(atlas.holders.keys).to include("neu:cf2")
      expect(atlas.holders.keys).not_to include("neu:cf")
    end
  end

  it "refuses a demo pid file that does not exist" do
    env = tui_env("THESEUS_RUN_DIR" => @dir, "THESEUS_DEMO_PIDS" => File.join(@dir, "nope.yml"))
    tui = described_class.new(config: Theseus::Config.new(env), out: out, prompt: prompt, atlas: atlas, v1: v1,
                              now: tui_now, tty: false, pastel: Pastel.new(enabled: false))
    expect(tui.run).to eq(2)
    expect(out.string).to include("THESEUS_DEMO_PIDS", "does not exist")
  end

  it "takes the v2 links from CERBERUS_URL" do
    env = tui_env("THESEUS_RUN_DIR" => @dir, "CERBERUS_URL" => "https://cerberus.example/")
    tui = described_class.new(config: Theseus::Config.new(env), out: out, prompt: prompt, atlas: atlas, v1: v1,
                              now: tui_now, tty: false, pastel: Pastel.new(enabled: false))
    answer("neu:cf", "y", "n")
    tui.run
    expect(out.string).to include("https://cerberus.example/works/n3")
  end
end
