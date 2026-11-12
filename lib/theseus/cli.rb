# frozen_string_literal: true

require "optparse"

module Theseus
  # `theseus <command> <pid> [options]`. Returns an exit status; never calls
  # `exit` itself, so specs can drive it.
  class CLI
    USAGE = <<~TEXT
      Usage:
        theseus lookup PID                 print the v1 chain from PID up to neu:1
        theseus export PID                 print PID's v1 MODS
        theseus import PID [--into NOID] [--force]
                                           create PID, and any missing ancestors, in v2
    TEXT

    COMMANDS = %w[lookup export import].freeze

    def initialize(argv, out: $stdout, err: $stderr, env: ENV)
      @argv = argv.dup
      @out = out
      @err = err
      @env = env
    end

    def run
      options = parse_options
      command, pid = @argv
      return usage_error unless COMMANDS.include?(command) && pid && @argv.size == 2

      send("run_#{command}", pid, options)
      0
    rescue OptionParser::ParseError => e
      usage_error(e.message)
    rescue Error => e
      @err.puts("theseus: #{e.message}")
      e.exit_status
    end

    private

      def parse_options
        options = { into: nil, force: false }
        OptionParser.new do |o|
          o.on("--into NOID") { |v| options[:into] = v }
          o.on("--force") { options[:force] = true }
        end.parse!(@argv)
        options
      end

      def usage_error(message = nil)
        @err.puts("theseus: #{message}") if message
        @err.puts(USAGE)
        1
      end

      def config = @config ||= Config.new(@env)

      def run_lookup(_pid, _options)
        raise Error, "lookup is not built yet"
      end

      def run_export(_pid, _options)
        raise Error, "export is not built yet"
      end

      def run_import(_pid, _options)
        raise Error, "import is not built yet"
      end
  end
end
