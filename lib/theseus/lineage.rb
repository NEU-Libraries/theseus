# frozen_string_literal: true

module Theseus
  # Walks a v1 pid up through its parents until it reaches an ancestor that
  # v2 already has (`known`), or the top of the v1 tree.
  #
  # Every link is checked on the way up. Nothing here writes to v2, so a bad
  # link stops the run before anything is created.
  class Lineage
    # Which v1 types may hold which. A CoreFile's parent is a Collection; a
    # Collection's is a Collection or a Community; a Community's a Community.
    PARENT_TYPES = {
      core_file: %i[collection],
      collection: %i[collection community],
      community: %i[community]
    }.freeze
    MAX_DEPTH = 25

    # objects - the walked objects, the starting pid first.
    # anchor_pid / anchor_type - the known ancestor the walk stopped at, or nil
    #   when it ran off the top of the v1 tree.
    Chain = Struct.new(:objects, :anchor_pid, :anchor_type, keyword_init: true) do
      def top_down = objects.reverse
    end

    # known - called with a pid; answers its type (:community, :collection,
    #   :core_file) when v2 already has it, else nil.
    def initialize(client, known: ->(_pid) {}, listener: NULL_LISTENER)
      @client = client
      @known = known
      @listener = listener
    end

    def walk(pid)
      objects = []
      seen = {}
      current = pid

      loop do
        if (type = @known.call(current))
          check_link!(objects.last, type) if objects.any?
          return Chain.new(objects: objects, anchor_pid: current, anchor_type: type)
        end

        raise FindingError.new(pid, "cyclic_ancestry", "the chain returns to #{current}") if seen[current]
        raise FindingError.new(pid, "ancestry_too_deep", "more than #{MAX_DEPTH} levels") if objects.size >= MAX_DEPTH

        seen[current] = true
        emit(:lookup_started, pid: current)
        object = V1Object.from_solr(@client.solr_document(current))
        check_type!(object)
        check_link!(objects.last, object.type) if objects.any?
        emit(:looked_up, object: object)
        objects << object

        return Chain.new(objects: objects, anchor_pid: nil, anchor_type: nil) if object.parent_pid.nil?

        current = object.parent_pid
      end
    end

    private

      def emit(name, **payload) = @listener.call(Event.new(name, payload))

      def check_type!(object)
        return if object.type

        raise FindingError.new(object.pid, "unsupported_model",
                               "#{object.model.inspect} is not a phase 1 type")
      end

      def check_link!(child, parent_type)
        return if PARENT_TYPES.fetch(child.type).include?(parent_type)

        raise FindingError.new(child.pid, "invalid_parent_type",
                               "a #{child.type} cannot sit under a #{parent_type} (#{child.parent_pid})")
      end
  end
end
