# frozen_string_literal: true

require "tmpdir"
require_relative "../../support_tui"

RSpec.describe Theseus::TUI, "when something goes wrong" do
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

  it "shows a finding in a yellow box, then asks for another pid" do
    v1.records["neu:cf"][3] = nil # no handle in the MODS
    answer("neu:cf", "neu:cf2", "y", "n")
    expect(tui.run).to eq(0)

    expect(out.string).to include("Not migrated: missing_v1_handle", "│ neu:cf ", "Nothing was written to v2.")
    expect(out.string).to include("✔ migrated")
    expect(atlas.holders.keys).to include("neu:cf2")
    expect(atlas.holders.keys).not_to include("neu:cf")
  end

  it "closes the open step with a cross" do
    v1.records["neu:cf"][2] = "neu:466" # a CoreFile cannot sit under a Community
    answer("neu:cf", "neu:cf2", "y", "n")
    expect(tui.run).to eq(0)

    expect(out.string).to include("✖ neu:466", "Not migrated: invalid_parent_type")
  end

  it "stops talking to v1 after a block, and offers only quit" do
    allow(v1).to receive(:solr_document).and_raise(Theseus::V1BlockedError.new(418, "/api/v1/files/neu:cf"))
    answer("neu:cf", "q")
    expect(tui.run).to eq(3)

    expect(out.string).to include("v1 refused", "Theseus has stopped talking to v1", "THESEUS_V1_REPLAY")
    expect(prompt.output.string).to include("Press any key to quit.")
    expect(prompt.output.string).not_to include("Migrate another?")
  end

  it "names the shell to remove when an Atlas write fails" do
    atlas.fail_on = :put_mods
    answer("neu:cf", "y", "q")
    expect(tui.run).to eq(5)

    expect(out.string).to include("Atlas refused", "Remove n1 in Cerberus before you try this pid again.")
    expect(out.string).to include("✖ Community  University Library")
  end

  it "names the variable when the configuration fails mid-run" do
    allow(v1).to receive(:solr_document).and_raise(Theseus::V1AuthError, "v1 answered 401: V1_JWT is bad or expired")
    answer("neu:cf", "q")
    expect(tui.run).to eq(2)
    expect(out.string).to include("Theseus has to stop", "V1_JWT is bad or expired", "Fix .env")
  end
end
