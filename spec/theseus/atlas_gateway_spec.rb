# frozen_string_literal: true

require "theseus/atlas_gateway"

RSpec.describe Theseus::AtlasGateway do
  subject(:gateway) { described_class.new }

  def response(status, body) = instance_double(Faraday::Response, status: status, body: body)

  def pid_error(code, status, holder = nil)
    body = JSON.generate({ "error" => code, "resource_id" => holder }.compact)
    AtlasRb::LegacyPidError.new("refused", JSON.parse(body), response: response(status, body))
  end

  it "sends the pid on a create and answers the new object" do
    allow(AtlasRb::Community).to receive(:create).and_return({ "id" => "c1", "legacy_pid" => "neu:466" })
    expect(gateway.create_community("root", legacy_pid: "neu:466")).to include("id" => "c1")
    expect(AtlasRb::Community).to have_received(:create).with("root", legacy_pid: "neu:466")
  end

  it "names the holder when the pid is taken" do
    allow(AtlasRb::Collection).to receive(:create).and_raise(pid_error("legacy_pid_taken", 409, "abc1234"))
    expect { gateway.create_collection("c1", legacy_pid: "neu:col") }
      .to raise_error(described_class::PidTaken) { |e| expect(e.holder_id).to eq("abc1234") }
  end

  it "reports an invalid pid as a plain failure" do
    allow(AtlasRb::Community).to receive(:create).and_raise(pid_error("invalid_legacy_pid", 422))
    expect { gateway.create_community("root", legacy_pid: "bogus") }
      .to raise_error(described_class::Failure, /422 \(invalid_legacy_pid\)/) { |e|
        expect(e).not_to be_a(described_class::PidTaken)
      }
  end

  it "asks for an admin token when Atlas will not record the pid" do
    error = AtlasRb::ForbiddenError.new("forbidden", code: "forbidden", action: "supply_legacy_pid")
    allow(AtlasRb::Work).to receive(:create).and_raise(error)
    expect { gateway.create_work("c1", idempotency_key: "k", handle: "2047/D1", legacy_pid: "neu:cf") }
      .to raise_error(Theseus::ConfigError, /ATLAS_JWT must be an admin's/)
  end

  it "answers nil for a pid nothing holds" do
    allow(AtlasRb::Resource).to receive(:find_by_legacy_pid).with("neu:1").and_return(nil)
    expect(gateway.find_by_legacy_pid("neu:1")).to be_nil
  end
end
