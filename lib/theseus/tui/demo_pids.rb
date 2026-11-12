# frozen_string_literal: true

require "yaml"

module Theseus
  class TUI
    # The pids a demo offers at the prompt, each with a note for the
    # presenter, read from the YAML file THESEUS_DEMO_PIDS names:
    #
    #   - pid: neu:cj82kh734
    #     note: "Newspaper issue, 8 levels deep: shows the whole ancestry"
    module DemoPids
      Pid = Struct.new(:pid, :note)

      def self.load(path)
        return [] if path.nil?
        raise ConfigError, "THESEUS_DEMO_PIDS: #{path} does not exist." unless File.exist?(path)

        entries = YAML.safe_load_file(path)
        raise ConfigError, "THESEUS_DEMO_PIDS: #{path} must be a list of pid and note." unless entries.is_a?(Array)

        entries.map do |entry|
          pid = entry.is_a?(Hash) && entry["pid"].to_s.strip
          raise ConfigError, "THESEUS_DEMO_PIDS: #{path} has an entry with no valid pid." unless V1Client::PID.match?(pid.to_s)

          Pid.new(pid, entry["note"].to_s.strip)
        end
      rescue Psych::SyntaxError => e
        raise ConfigError, "THESEUS_DEMO_PIDS: #{path} is not valid YAML (#{e.message})."
      end
    end
  end
end
