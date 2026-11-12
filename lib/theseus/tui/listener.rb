# frozen_string_literal: true

module Theseus
  class TUI
    # Turns the core's events into the TUI's steps: a spinner per v1 lookup,
    # one for the MODS checks, and one per create. Whatever step is open when
    # an error lands is closed with a cross by #fail_open.
    class Listener
      HANDLE_HOST = %r{\Ahttps?://hdl\.handle\.net/}

      def initialize(screen)
        @screen = screen
        @open = nil
        @mods = 0
      end

      def call(event)
        handler = "on_#{event.name}"
        send(handler, event) if respond_to?(handler, true)
      end

      # The plan is made: close the MODS step and say what was checked.
      def checks_done(plan)
        close(:success, "#{@mods} #{@mods == 1 ? 'record' : 'records'} · fetched · well-formed · saved as evidence")
        work = plan.items.find { |item| item.object.type == :core_file }
        @screen.done("Handle".ljust(16), "#{bare(work.handle)}, from the CoreFile's MODS") if work
        @screen.done("Parent types".ljust(16), "every link valid")
      end

      def fail_open = close(:error)

      private

        def on_lookup_started(event) = open(event[:pid].ljust(14))

        def on_looked_up(event)
          object = event[:object]
          handle = object.handle ? @screen.dim(" hdl #{bare(object.handle)}") : ""
          close(:success, "#{@screen.kind(object.type)} #{@screen.cut(object.title, 30).ljust(30)}#{handle}".rstrip)
        end

        def on_anchor_reached(event)
          @screen.mark(@screen.green("●"), "#{event[:pid].ljust(14)} #{@screen.green("already in v2 · #{event[:noid]}")}")
          @screen.section(2, "Check every record", "before anything is written")
          open("MODS".ljust(16))
        end

        def on_mods_checked(_event) = @mods += 1

        def on_create_started(event)
          object = event[:object]
          open("#{@screen.kind(object.type)} #{@screen.cut(object.title, 36).ljust(36)}")
        end

        def on_created(event)
          text = @screen.bold(event[:noid])
          text += @screen.dim(" · completed") if event[:object].type == :core_file
          text += @screen.yellow(" · #{event[:outcome]}") unless event[:outcome] == "created"
          close(:success, text)
        end

        def open(label)
          close(:success)
          @open = @screen.step(label)
        end

        def close(how, text = "")
          step = @open
          @open = nil
          step&.public_send(how, text)
        end

        def bare(handle) = handle.to_s.sub(HANDLE_HOST, "")
    end
  end
end
