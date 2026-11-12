# frozen_string_literal: true

module Theseus
  # Reads Theseus's settings from the environment (and `.env`, loaded by the
  # CLI). Each command asks only for what it needs.
  class Config
    V1_VARS = %w[V1_URL V1_JWT].freeze
    V2_VARS = %w[ATLAS_URL ATLAS_JWT].freeze
    # Read before Theseus sent v1 pids to Atlas. Atlas now finds the root by
    # neu:1, and the run log replaced the map.
    OBSOLETE_VARS = %w[V2_ROOT THESEUS_MAP].freeze
    DEFAULT_RUN_DIR = "runs"

    def initialize(env = ENV)
      @env = env
    end

    def require_v1!
      require_vars!(V1_VARS)
      V1Token.new(v1_jwt).check!
      self
    end

    def require_v2!
      require_vars!(V2_VARS)
      self
    end

    def replay_dir = value("THESEUS_V1_REPLAY")
    def record_dir = value("THESEUS_V1_RECORD")
    def replay? = !replay_dir.nil?

    # Where v1 answers come from: a recording (THESEUS_V1_REPLAY), which needs
    # no token, or live v1, saving each answer when THESEUS_V1_RECORD is set.
    def v1_reader
      raise ConfigError, "Set THESEUS_V1_REPLAY or THESEUS_V1_RECORD, not both." if replay? && record_dir
      return V1Replay.new(replay_dir) if replay?

      require_v1!
      client = V1Client.new(base_url: v1_url, token: v1_jwt)
      record_dir ? V1Recorder.new(client, record_dir) : client
    end

    def v1_url = @env.fetch("V1_URL")
    def v1_jwt = @env.fetch("V1_JWT")

    # Where an import keeps its log and the MODS it exported.
    def run_dir
      dir = @env["THESEUS_RUN_DIR"].to_s.strip
      dir.empty? ? DEFAULT_RUN_DIR : dir
    end

    def obsolete_vars = OBSOLETE_VARS.reject { |name| @env[name].to_s.strip.empty? }

    private

      def value(name)
        text = @env[name].to_s.strip
        text.empty? ? nil : text
      end

      def require_vars!(names)
        missing = names.select { |name| @env[name].to_s.strip.empty? }
        return if missing.empty?

        raise ConfigError, "Set #{missing.join(', ')} (see .env.example)."
      end
  end
end
