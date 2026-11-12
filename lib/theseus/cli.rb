# frozen_string_literal: true

require "optparse"

module Theseus
  # `theseus <command> <pid> [options]`. Returns an exit status; never calls
  # `exit` itself, so specs can drive it.
  class CLI
    USAGE = <<~TEXT
      Usage:
        theseus                            the guided TUI, for demos (also: theseus tui)
        theseus lookup PID                 print the v1 chain from PID up to neu:1
        theseus export PID                 print PID's v1 MODS
        theseus import PID [--into NOID] [--force]
                                           create PID, and any missing ancestors, in v2
    TEXT

    COMMANDS = %w[lookup export import].freeze

    def initialize(argv, out: $stdout, err: $stderr, env: ENV, tty: $stdin.tty? && $stdout.tty?)
      @argv = argv.dup
      @out = out
      @err = err
      @env = env
      @tty = tty
    end

    def run
      return run_tui if @argv.empty? || @argv == ["tui"]

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

      # A TUI drawn into a pipe is noise, so off a terminal this is a usage error.
      def run_tui
        return usage_error("the TUI needs a terminal; use a command below instead") unless @tty

        require_relative "tui" # loads the TTY toolkit and atlas_rb, which only the TUI needs
        TUI.new(config: config, out: @out).run
      end

      def v1_client = config.v1_reader

      def run_lookup(pid, _options)
        chain = Lineage.new(v1_client).walk(pid)
        chain.objects.each do |object|
          @out.puts([object.pid.ljust(16), object.type.to_s.ljust(11), object.title,
                     object.handle && "(#{object.handle})"].compact.join(" "))
        end
      end

      # MODS to stdout; what import would make of it to stderr.
      def run_export(pid, _options)
        client = v1_client
        object = V1Object.from_solr(client.solr_document(pid))
        xml = client.mods(pid)
        handle = Mods.handle(pid, xml)
        @out.write(xml)
        @out.puts unless xml.end_with?("\n")
        @err.puts("#{pid}: #{object.model}, handle #{handle || 'none'}")
        return unless object.type == :core_file && handle.nil?

        @err.puts("#{pid}: import would refuse this CoreFile: missing_v1_handle")
      end

      def run_import(pid, options)
        client = v1_client
        config.require_v2!
        obsolete = config.obsolete_vars
        @err.puts("theseus: ignoring #{obsolete.join(', ')}; Theseus now asks Atlas for neu:1.") if obsolete.any?
        require_relative "atlas_gateway" # loads atlas_rb, which only import needs
        Importer.new(v1: client, atlas: AtlasGateway.new, log: RunLog.new(config.run_dir),
                     mods_dir: File.join(config.run_dir, "mods"), listener: CLIListener.new(@out))
                .run(pid, into: options[:into], force: options[:force])
      end
  end
end
