# frozen_string_literal: true

require "uri"

module Theseus
  class TUI
    # The checks the TUI runs before it draws the header. Each answers one of
    # the header's four facts, or stops the TUI with a configuration error
    # that names what to fix.
    class Preflight
      MIN_TOKEN_LEFT = 15 * 60

      Status = Struct.new(:v1, :token, :atlas, :root, :root_noid, keyword_init: true)

      def initialize(config, atlas:, now: -> { Time.now })
        @config = config
        @atlas = atlas
        @now = now
      end

      def run
        v1, token = v1_facts
        atlas, root, root_noid = atlas_facts
        Status.new(v1: v1, token: token, atlas: atlas, root: root, root_noid: root_noid)
      end

      private

        def v1_facts
          return ["replay: #{@config.replay_dir}", "not needed"] if @config.replay?

          @config.require_v1!(now: @now)
          left = V1Token.new(@config.v1_jwt).expires_at - @now.call
          if left < MIN_TOKEN_LEFT
            raise ConfigError, "V1_JWT has #{(left / 60).floor} minutes left, and a demo needs at least " \
                               "#{MIN_TOKEN_LEFT / 60}. Mint a new one (v1: My Loaders -> API Token)."
          end

          [host(@config.v1_url), "#{duration(left)} left"]
        end

        def atlas_facts
          @config.require_v2!
          health = ask_atlas("/health") { @atlas.health }
          root = ask_atlas("neu:1") { @atlas.find_by_legacy_pid(Importer::ROOT_PID) }
          raise ConfigError, "Atlas holds nothing for neu:1. Reset dev: the reset creates the root with it." unless root
          unless root["type"] == "Community"
            raise ConfigError, "Atlas has neu:1 as #{root['id']}, a #{root['type']}, not a Community."
          end

          community = ask_atlas("the root") { @atlas.find_community(root["id"]) }
          ["#{host(@config.atlas_url)} · health #{health}", community&.fetch("title", nil) || "(untitled)", root["id"]]
        end

        def ask_atlas(what)
          yield
        rescue AtlasGateway::Failure => e
          raise ConfigError, "Atlas at ATLAS_URL did not answer for #{what}: #{e.message}"
        end

        def host(url)
          uri = URI(url)
          [80, 443].include?(uri.port) ? uri.host : "#{uri.host}:#{uri.port}"
        end

        def duration(seconds)
          minutes = (seconds / 60).floor
          minutes >= 60 ? "#{minutes / 60}h #{minutes % 60}m" : "#{minutes}m"
        end
    end
  end
end
