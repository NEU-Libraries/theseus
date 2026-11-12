# frozen_string_literal: true

require "tty-prompt"
require_relative "atlas_gateway"
require_relative "tui/screen"
require_relative "tui/preflight"
require_relative "tui/listener"

module Theseus
  # The demo front end: `bin/theseus` with no arguments, or `bin/theseus tui`.
  # A guided, scrolling run over the same core as the CLI. Returns an exit
  # status, as CLI#run does.
  class TUI
    ROUTES = { community: "communities", collection: "collections", core_file: "works" }.freeze
    V1_ROUTES = ROUTES.merge(core_file: "files").freeze

    def initialize(config:, out: $stdout, input: $stdin, prompt: nil, atlas: AtlasGateway.new, v1: nil,
                   now: -> { Time.now }, tty: nil, pastel: Pastel.new)
      @config = config
      @screen = Screen.new(out, pastel: pastel, **{ tty: tty }.compact)
      @prompt = prompt || TTY::Prompt.new(input: input, output: out, interrupt: :exit)
      @atlas = atlas
      @v1 = v1
      @now = now
    end

    def run
      @status = Preflight.new(@config, atlas: @atlas, now: @now).run
      @v1 ||= @config.v1_reader
      @screen.header(@status)
      loop do
        migrate(ask_pid)
        break unless @prompt.yes?("Migrate another?")
      end
      0
    rescue ConfigError, V1AuthError => e
      stop_box("Theseus cannot start", e)
      e.exit_status
    end

    private

      def ask_pid
        @screen.puts
        @prompt.ask("v1 pid to migrate:", required: true) do |q|
          q.validate(V1Client::PID, "Enter a v1 pid, such as neu:cj82kh734")
        end.strip
      end

      def migrate(pid)
        listener = Listener.new(@screen)
        log = RunLog.new(@config.run_dir)
        importer = Importer.new(v1: @v1, atlas: @atlas, log: log, mods_dir: File.join(@config.run_dir, "mods"),
                                listener: listener)

        @screen.section(1, "Trace the v1 ancestry",
                        @config.replay? ? "read-only · from the recording" : "read-only · one request a second")
        started = @now.call
        plan = importer.plan(pid)
        listener.checks_done(plan)
        working = @now.call - started

        show_plan(plan)
        return unless @prompt.yes?("Create them now?")

        @screen.section(4, "Create in v2")
        started = @now.call
        steps = importer.execute(plan)
        work = steps.find { |step| step.object.type == :core_file }
        @screen.done("Handle check".ljust(47), "#{work.handle} · kept, nothing minted") if work
        summary(plan, steps, working + (@now.call - started), log)
      rescue StandardError
        listener&.fail_open
        raise
      end

      def show_plan(plan)
        count = plan.items.size
        @screen.section(3, "The plan",
                        "create #{count} #{count == 1 ? 'object' : 'objects'} under #{plan.parent_noid}, top-down")
        rows = plan.objects.each_with_index.map do |object, depth|
          [object.pid, @screen.kind(object.type).rstrip, "#{' ' * depth}└ #{@screen.cut(object.title, 36)}"]
        end
        @screen.table(["v1 pid", "v2 type", "where it lands in v2"], rows)
        @screen.mark(@screen.yellow("!"), "Phase 1 copies no permissions: every object is public in dev.")
      end

      def summary(plan, steps, seconds, log)
        last = steps.last
        object = last.object
        route = ROUTES.fetch(object.type)
        lines = [
          @screen.bold(object.title),
          "#{@screen.dim('v2 page'.ljust(10))} #{@config.cerberus_url}/#{route}/#{last.noid}",
          "#{@screen.dim('v1 URL'.ljust(10))} /#{V1_ROUTES.fetch(object.type)}/#{plan.pid}  →  " \
          "/#{route}/#{last.noid}  #{@screen.dim('(redirects now)')}"
        ]
        if last.handle
          lines << "#{@screen.dim('handle'.ljust(10))} https://hdl.handle.net/#{last.handle}  #{@screen.dim('(unchanged)')}"
        end
        lines << "#{counts(steps)} · #{format('%.1f', seconds)} s · log: #{log.path}"
        @screen.box(@screen.green("✔ migrated"), lines.join("\n"), :green)
      end

      def counts(steps)
        tally = steps.map(&:outcome).tally
        created = tally.delete("created").to_i
        ["#{created} #{created == 1 ? 'object' : 'objects'} created", *tally.map { |outcome, n| "#{n} #{outcome}" }]
          .join(", ")
      end

      def stop_box(title, error)
        @screen.box(title, "#{error.message}\n\nFix .env and start Theseus again.", :red)
      end
  end
end
