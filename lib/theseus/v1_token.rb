# frozen_string_literal: true

require "base64"
require "json"

module Theseus
  # The v1 API token. v1 does not check it until a request lands, and an
  # expired one fails partway through a run, so Theseus reads `exp` first.
  # The signature is v1's business; Theseus only reads the claims.
  class V1Token
    def initialize(jwt, now: -> { Time.now })
      @jwt = jwt.to_s.strip
      @now = now
    end

    def expires_at
      Time.at(Integer(claims.fetch("exp")))
    rescue KeyError, ArgumentError, TypeError
      raise ConfigError, "V1_JWT has no usable exp claim."
    end

    def check!
      return self if expires_at > @now.call

      raise ConfigError, "V1_JWT expired at #{expires_at}. Mint a new one " \
                         "(v1: My Loaders -> API Token)."
    end

    private

      def claims
        payload = @jwt.split(".")[1]
        raise ConfigError, "V1_JWT is not a JWT." if payload.nil?

        JSON.parse(Base64.urlsafe_decode64(payload + ("=" * (-payload.length % 4))))
      rescue JSON::ParserError, ArgumentError
        raise ConfigError, "V1_JWT is not a JWT."
      end
  end
end
