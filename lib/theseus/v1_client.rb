# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Theseus
  # Reads from v1 (cerberus-classic) production. Read-only, one request at a
  # time, paced, and it stops at the first sign that v1's bot defences have
  # noticed it.
  #
  # Three v1 quirks shape this class (see the phase 1 design):
  #
  # - v1 reads the token from the `token` query parameter only. A token in an
  #   Authorization header is ignored and the request runs as a guest.
  # - Rack::Attack ignores the token. Theseus passes its session-cookie
  #   safelist, which accepts any cookie containing "shibsession".
  # - A refusal is a JSON `error` body with HTTP 200, not a 4xx.
  class V1Client
    PID = /\Aneu:[a-z0-9]+\z/
    MIN_INTERVAL = 1.0
    BLOCKED = [403, 418, 503].freeze
    COOKIE = "_shibsession_theseus=1"

    # Refuses anything that is not a v1 pid, before it reaches a URL or a
    # file name.
    def self.check_pid!(pid)
      return pid if PID.match?(pid.to_s)

      raise FindingError.new(pid, "invalid_pid", "not a v1 pid (expected neu:...)")
    end

    def initialize(base_url:, token:, min_interval: MIN_INTERVAL,
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                   sleeper: ->(seconds) { sleep(seconds) })
      @base = URI(base_url.to_s.chomp("/"))
      @token = token
      @min_interval = min_interval
      @clock = clock
      @sleeper = sleeper
      @last_request_at = nil
    end

    # The pid's Solr document (the `_source` of `?solr_only=true`).
    def solr_document(pid)
      body = get(pid, "/api/v1/files/#{check_pid(pid)}", { solr_only: "true" })
      data = parse_json(pid, body)
      refuse_if_error!(pid, data)
      data.fetch("_source") { raise V1Error, "#{pid}: the Solr document has no _source" }
    end

    # The pid's newest MODS, as XML text.
    def mods(pid)
      body = get(pid, "/api/v1/files/#{check_pid(pid)}/mods", {})
      if body.lstrip.start_with?("{")
        refuse_if_error!(pid, parse_json(pid, body))
        raise V1Error, "#{pid}: v1 answered JSON, not MODS"
      end
      body
    end

    private

      def check_pid(pid) = self.class.check_pid!(pid)

      def get(pid, path, query)
        pace!
        uri = @base.dup
        uri.path = @base.path + path
        uri.query = URI.encode_www_form(query.merge(token: @token))
        response = http_get(uri)
        check_status!(pid, path, response)
        response.body.to_s.dup.force_encoding(Encoding::UTF_8)
      end

      def http_get(uri)
        request = Net::HTTP::Get.new(uri)
        request["Cookie"] = COOKIE
        request["User-Agent"] = "theseus/#{VERSION}"
        request["Accept"] = "application/json, application/xml"
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                            open_timeout: 15, read_timeout: 60) do |http|
          http.request(request)
        end
      end

      # Error messages name the path only. The full URL carries the token.
      def check_status!(pid, path, response)
        status = response.code.to_i
        return if status == 200

        raise V1BlockedError.new(status, path) if BLOCKED.include?(status)
        raise V1AuthError, "v1 answered 401 for #{path}: V1_JWT is bad or expired" if status == 401

        raise V1Error, "#{pid}: v1 answered #{status} for #{path}"
      end

      def pace!
        now = @clock.call
        if @last_request_at
          wait = @min_interval - (now - @last_request_at)
          @sleeper.call(wait) if wait.positive?
        end
        @last_request_at = @clock.call
      end

      def parse_json(pid, body)
        JSON.parse(body)
      rescue JSON::ParserError
        raise V1Error, "#{pid}: v1 answered something that is not JSON"
      end

      def refuse_if_error!(pid, data)
        return unless data.is_a?(Hash)

        message = data["error"] || Array(data["errors"]).join("; ")
        return if message.to_s.empty?

        raise FindingError.new(pid, "v1_refused", message)
      end
  end
end
