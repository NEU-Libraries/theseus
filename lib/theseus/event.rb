# frozen_string_literal: true

module Theseus
  # Something Lineage or Importer did, reported to a listener: any object with
  # #call(event). The CLI prints some of them; the TUI draws all of them.
  #
  #   :lookup_started  pid                       Lineage, before each v1 lookup
  #   :looked_up       object (V1Object)         Lineage, once its links check out
  #   :anchor_reached  pid, noid                 Importer, at the ancestor Atlas holds
  #   :mods_checked    pid, handle               Importer, per exported MODS
  #   :create_started  object, parent_noid       Importer, before each create
  #   :completed       pid, noid, handle         Importer, after a Work's handle check
  #   :created         object, noid, outcome     Importer, as each step returns
  Event = Struct.new(:name, :payload) do
    def [](key) = payload.fetch(key)
  end

  NULL_LISTENER = ->(_event) {}

  # Prints the lines `theseus import` has always printed: one per object.
  class CLIListener
    def initialize(out)
      @out = out
    end

    def call(event)
      return unless event.name == :created

      object = event[:object]
      note = event[:outcome] == "created" ? "" : " [#{event[:outcome]}]"
      @out.puts("#{object.pid} -> #{event[:noid]} (#{object.map_type}) #{object.title}#{note}")
    end
  end
end
