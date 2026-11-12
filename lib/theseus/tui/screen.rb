# frozen_string_literal: true

require "pastel"
require "strings"
require "tty-box"
require "tty-screen"
require "tty-spinner"
require "tty-table"

module Theseus
  class TUI
    # Draws the TUI's pieces: the header, section titles, steps, the plan
    # table and boxes. On a terminal a step is a spinner; anywhere else it is
    # one plain line when it ends, so specs and recordings read cleanly.
    # Pastel honours NO_COLOR.
    class Screen
      WIDTH = 76
      COLOURS = { community: :magenta, collection: :cyan, core_file: :yellow }.freeze
      V2_TYPES = { community: "Community", collection: "Collection", core_file: "Work" }.freeze

      attr_reader :out, :pastel

      def initialize(out, tty: out.respond_to?(:tty?) && out.tty?, pastel: Pastel.new)
        @out = out
        @tty = tty
        @pastel = pastel
      end

      def tty? = @tty

      def width = [tty? ? TTY::Screen.width : WIDTH, WIDTH].min

      def puts(text = "") = @out.puts(text)

      def header(status)
        frame = TTY::Box.frame(width: width, padding: [0, 1], border: :thick,
                               title: { top_left: " THESEUS · v1 → v2 ", top_right: " phase 1 " }) do
          rows = [["v1", status.v1, "token", status.token], ["v2", status.atlas, "root", status.root]]
          right = width - 4 - 4 - 38 - 7 # borders and padding, "v1  ", the left value, "token "
          rows.map { |a, b, c, d| "#{dim(a)}  #{cut(b, 36).ljust(38)}#{dim(c.ljust(6))} #{cut(d, right)}" }.join("\n")
        end
        @out.print(frame)
      end

      def section(number, title, note = nil)
        puts
        puts("#{bold("#{number}  #{title}")}#{note ? "  #{dim(note)}" : ''}")
      end

      # A step that is started now and ended later, perhaps by another event.
      def step(label) = Step.new(self, label)

      def done(label, result) = @out.puts("  #{green('✔')} #{label} #{result}")
      def mark(symbol, text) = @out.puts("  #{symbol} #{text}")

      def table(header, rows)
        puts(TTY::Table.new(header: header.map { |h| dim(h) }, rows: rows).render(:unicode, padding: [0, 1], indent: 2))
      end

      def box(title, text, colour)
        puts
        @out.print(TTY::Box.frame(width: width, padding: [0, 1], border: :light,
                                  title: { top_left: pastel.decorate(" #{title} ", colour) }) { wrap(text) })
      end

      # tty-box sizes a frame from its lines before it wraps them, so a long
      # line would push the last ones out. Wrap first.
      def wrap(text) = Strings.wrap(text, width - 4)

      # The v2 type of a phase 1 type, in its colour, padded to line up.
      def kind(type) = pastel.decorate(V2_TYPES.fetch(type).ljust(10), COLOURS.fetch(type))

      def cut(text, size)
        text = text.to_s
        text.length > size ? "#{text[0, size - 1]}…" : text
      end

      %i[bold dim green red yellow cyan].each do |style|
        define_method(style) { |text| pastel.decorate(text.to_s, style) }
      end

      # One line of progress: a spinner on a terminal, a plain line elsewhere.
      class Step
        def initialize(screen, label)
          @screen = screen
          @label = label
          return unless screen.tty?

          @spinner = TTY::Spinner.new("  :spinner #{label}", output: screen.out, format: :dots, hide_cursor: true,
                                                              success_mark: screen.green("✔"),
                                                              error_mark: screen.red("✖"))
          @spinner.auto_spin
        end

        def success(result = "")
          return @spinner.success(result.to_s) if @spinner

          @screen.done(@label, result)
        end

        def error(result = "")
          return @spinner.error(result.to_s) if @spinner

          @screen.mark(@screen.red("✖"), "#{@label} #{result}".rstrip)
        end
      end
    end
  end
end
