# frozen_string_literal: true

module Theseus
  # Every failure Theseus reports carries an exit status, so the CLI maps an
  # error to a status in one place.
  #
  # 2 - configuration (missing variable, expired token)
  # 3 - v1 refused at the network layer; the run must stop and not retry
  # 4 - a finding about the source data (refused, wrong shape, no handle)
  # 5 - a v2 failure, possibly leaving something behind in Atlas
  class Error < StandardError
    def exit_status = 1
  end

  class ConfigError < Error
    def exit_status = 2
  end

  # v1 answered 401: the token is bad or expired.
  class V1AuthError < Error
    def exit_status = 2
  end

  # v1's Rack::Attack refused the request (403, 418 or 503). Three 418s from
  # one IP block it for 24 hours, so the run stops at the first one.
  class V1BlockedError < Error
    attr_reader :status

    def initialize(status, path)
      @status = status
      super("v1 answered #{status} for #{path}. Stopping; do not retry until you " \
            "know why (three 418s block this IP for 24 hours).")
    end

    def exit_status = 3
  end

  # Any other unexpected v1 status.
  class V1Error < Error
    def exit_status = 3
  end

  # A finding about the v1 record itself. The run stops and reports it; it is
  # not a Theseus bug.
  class FindingError < Error
    attr_reader :pid, :code, :detail

    def initialize(pid, code, message)
      @pid = pid
      @code = code
      @detail = message
      super("#{pid}: #{code}: #{message}")
    end

    def exit_status = 4
  end

  # Atlas refused or failed a write.
  class AtlasError < Error
    attr_reader :pid, :noid

    def initialize(pid, message, noid: nil)
      @pid = pid
      @noid = noid
      text = "#{pid}: #{message}"
      text += " A shell was left behind at #{noid}; remove it before re-running." if noid
      super(text)
    end

    def exit_status = 5
  end
end
