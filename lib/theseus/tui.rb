# frozen_string_literal: true

require "tty-prompt"
require_relative "atlas_gateway"
require_relative "tui/screen"
require_relative "tui/preflight"

module Theseus
  # The demo front end: `bin/theseus` with no arguments, or `bin/theseus tui`.
  # A guided, scrolling run over the same core as the CLI. Returns an exit
  # status, as CLI#run does.
  class TUI
    def initialize(config:, out: $stdout, input: $stdin, prompt: nil, atlas: AtlasGateway.new,
                   now: -> { Time.now }, tty: nil, pastel: Pastel.new)
      @config = config
      @screen = Screen.new(out, pastel: pastel, **{ tty: tty }.compact)
      @prompt = prompt || TTY::Prompt.new(input: input, output: out, interrupt: :exit)
      @atlas = atlas
      @now = now
    end

    def run
      @status = Preflight.new(@config, atlas: @atlas, now: @now).run
      @screen.header(@status)
      0
    rescue ConfigError, V1AuthError => e
      stop_box("Theseus cannot start", e)
      e.exit_status
    end

    private

      def stop_box(title, error)
        @screen.box(title, "#{error.message}\n\nFix .env and start Theseus again.", :red)
      end
  end
end
