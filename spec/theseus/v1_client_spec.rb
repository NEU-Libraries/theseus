# frozen_string_literal: true

RSpec.describe Theseus::V1Client do
  let(:base) { "https://v1.example" }
  let(:sleeps) { [] }
  let(:times) { [0.0] }
  let(:client) do
    described_class.new(base_url: base, token: "tok",
                        clock: -> { times.first }, sleeper: ->(s) { sleeps << s })
  end

  def solr_url(pid) = "#{base}/api/v1/files/#{pid}?solr_only=true&token=tok"

  describe "#solr_document" do
    it "sends the token as a query parameter, the cookie and its own user agent" do
      stub = stub_request(:get, solr_url("neu:1"))
             .with(headers: { "Cookie" => "_shibsession_theseus=1",
                              "User-Agent" => "theseus/#{Theseus::VERSION}" })
             .to_return(status: 200, body: { _source: { id: "neu:1" } }.to_json)

      expect(client.solr_document("neu:1")).to eq("id" => "neu:1")
      expect(stub).to have_been_requested
    end

    it "never sends an Authorization header" do
      stub_request(:get, solr_url("neu:1")).to_return(body: { _source: {} }.to_json)
      client.solr_document("neu:1")
      expect(a_request(:get, solr_url("neu:1")).with { |r| r.headers.key?("Authorization") })
        .not_to have_been_made
    end

    it "treats an error body with HTTP 200 as a refusal" do
      stub_request(:get, solr_url("neu:abc"))
        .to_return(status: 200, body: { error: "The item you've requested is unavailable." }.to_json)

      expect { client.solr_document("neu:abc") }
        .to raise_error(Theseus::FindingError, /neu:abc: v1_refused: The item/)
    end

    [403, 418, 503].each do |status|
      it "stops on a #{status} and does not retry" do
        stub = stub_request(:get, solr_url("neu:1")).to_return(status: status, body: "Forbidden\n")

        expect { client.solr_document("neu:1") }.to raise_error(Theseus::V1BlockedError) { |e|
          expect(e.status).to eq(status)
          expect(e.message).not_to include("tok")
        }
        expect(stub).to have_been_requested.once
      end
    end

    it "reports a 401 as a token problem" do
      stub_request(:get, solr_url("neu:1")).to_return(status: 401, body: '{"errors":["Not Authenticated"]}')
      expect { client.solr_document("neu:1") }.to raise_error(Theseus::V1AuthError)
    end

    it "refuses something that is not a v1 pid, without a request" do
      expect { client.solr_document("neu:1/../admin") }
        .to raise_error(Theseus::FindingError, /invalid_pid/)
    end
  end

  describe "#mods" do
    it "returns the MODS text" do
      stub_request(:get, "#{base}/api/v1/files/neu:1/mods?token=tok")
        .to_return(status: 200, body: "<mods:mods/>", headers: { "Content-Type" => "application/xml" })
      expect(client.mods("neu:1")).to eq("<mods:mods/>")
    end

    it "treats a JSON error body as a refusal" do
      stub_request(:get, "#{base}/api/v1/files/neu:1/mods?token=tok")
        .to_return(status: 200, body: '{"error": "The item you\'ve requested is unavailable."}')
      expect { client.mods("neu:1") }.to raise_error(Theseus::FindingError, /v1_refused/)
    end
  end

  describe "pacing" do
    it "waits out the rest of the interval between requests" do
      stub_request(:get, /v1\.example/).to_return(body: { _source: {} }.to_json)
      client.solr_document("neu:1")
      times[0] = 0.25
      client.solr_document("neu:2")
      expect(sleeps).to eq([0.75])
    end

    it "does not wait before the first request" do
      stub_request(:get, /v1\.example/).to_return(body: { _source: {} }.to_json)
      client.solr_document("neu:1")
      expect(sleeps).to be_empty
    end
  end
end
