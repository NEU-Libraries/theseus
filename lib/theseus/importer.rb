# frozen_string_literal: true

require "fileutils"

module Theseus
  # Imports one v1 pid, and any ancestors v2 lacks, into v2.
  #
  # The run has two halves. The first reads v1 only: it walks the ancestry,
  # fetches every MODS, checks it, and keeps a copy as evidence. The second
  # writes to Atlas, top-down. A finding in the first half stops the run with
  # nothing created.
  #
  # Atlas, not a local file, says what v2 already has: every object Theseus
  # creates holds its v1 pid as legacy_pid, and the walk asks Atlas for each
  # ancestor's pid in turn. The root answers to neu:1.
  class Importer
    Export = Struct.new(:object, :mods_path, :handle)
    Holder = Struct.new(:noid, :type)

    ROOT_PID = "neu:1"
    ATLAS_TYPES = { "Community" => :community, "Collection" => :collection, "Work" => :core_file }.freeze

    def initialize(v1:, atlas:, log:, mods_dir:, listener: NULL_LISTENER)
      @v1 = v1
      @atlas = atlas
      @log = log
      @mods_dir = mods_dir
      @listener = listener
    end

    def run(pid, into: nil, force: false)
      @holders = {}
      existing = holder(pid)
      if existing && !force
        raise FindingError.new(pid, "already_imported",
                               "Atlas has it as #{existing.noid}; pass --force to re-run")
      end

      objects, parent_noid = plan(pid, into)
      exports = objects.map { |object| export(object) }
      exports.each { |item| parent_noid = create(item, parent_noid, existing) }
    end

    private

      def plan(pid, into)
        if into
          object = V1Object.from_solr(@v1.solr_document(pid))
          raise FindingError.new(pid, "unsupported_model", "#{object.model.inspect} is not a phase 1 type") unless object.type

          return [[object], into]
        end

        check_root!
        # With --force Atlas already holds the pid itself, so it must not end the walk.
        known = ->(candidate) { candidate == pid ? nil : holder(candidate)&.type }
        chain = Lineage.new(@v1, known: known, listener: @listener).walk(pid)
        unless chain.anchor_pid
          top = chain.objects.last.pid
          raise FindingError.new(pid, "unanchored", "the chain ends at #{top}, which Atlas does not hold")
        end

        anchor_noid = holder(chain.anchor_pid).noid
        emit(:anchor_reached, pid: chain.anchor_pid, noid: anchor_noid)
        [chain.top_down, anchor_noid]
      end

      def check_root!
        root = holder(ROOT_PID)
        unless root
          raise ConfigError, "Atlas holds nothing for #{ROOT_PID}. Create the root Community with " \
                             "legacy_pid \"#{ROOT_PID}\" (Cerberus's reset:data does this)."
        end
        return if root.type == :community

        raise ConfigError, "Atlas has #{ROOT_PID} as #{root.noid}, a #{root.type}, not a Community."
      end

      # What Atlas holds for a pid, asked once per run. A tombstoned holder
      # stops the run: nothing may be created under it, or in its place.
      def holder(pid)
        return @holders[pid] if @holders.key?(pid)

        @holders[pid] = lookup(pid)
      end

      def lookup(pid)
        found = atlas(pid) { @atlas.find_by_legacy_pid(pid) }
        return nil unless found

        if found["tombstoned"]
          raise FindingError.new(pid, "tombstoned_in_v2", "Atlas holds it as #{found['id']}, which is tombstoned")
        end

        type = ATLAS_TYPES.fetch(found["type"]) do
          raise AtlasError.new(pid, "Atlas holds it as #{found['id']}, an unexpected #{found['type'].inspect}")
        end
        Holder.new(found.fetch("id"), type)
      end

      def export(object)
        xml = @v1.mods(object.pid)
        handle = Mods.handle(object.pid, xml)
        if object.type == :core_file && handle.nil?
          raise FindingError.new(object.pid, "missing_v1_handle",
                                 "the MODS has no <identifier type=\"hdl\">; v1 CoreFiles must have one")
        end

        FileUtils.mkdir_p(@mods_dir)
        path = File.join(@mods_dir, "#{object.pid.tr(':', '_')}.xml")
        File.write(path, xml)
        emit(:mods_checked, pid: object.pid, handle: handle)
        Export.new(object, path, handle)
      end

      def create(item, parent_noid, existing)
        object = item.object
        emit(:create_started, object: object, parent_noid: parent_noid)
        noid, outcome =
          if object.type == :core_file
            noid = create_work(item, parent_noid)
            [noid, existing&.noid == noid ? "replayed" : "created"]
          else
            create_container(item, parent_noid)
          end
        @log.append(object.pid, noid, object.map_type, outcome)
        emit(:created, object: object, noid: noid, outcome: outcome)
        noid
      end

      def create_container(item, parent_noid)
        object = item.object
        noid, outcome = begin
          [new_container(object, parent_noid), "created"]
        rescue AtlasGateway::PidTaken => e
          [adopt!(object, e.holder_id), "adopted"]
        end
        atlas(object.pid, noid) { @atlas.put_mods(noid, item.mods_path) }
        [noid, outcome]
      end

      def new_container(object, parent_noid)
        created =
          if object.type == :community
            @atlas.create_community(parent_noid, legacy_pid: object.pid)
          else
            @atlas.create_collection(parent_noid, legacy_pid: object.pid)
          end
        check_legacy_pid!(object.pid, created)
        created.fetch("id")
      rescue AtlasGateway::PidTaken
        raise
      rescue AtlasGateway::Failure => e
        raise AtlasError.new(object.pid, e.message)
      end

      # Atlas already holds the pid: a run that crashed after a create, or a
      # --force re-run. Carry on with the holder, after checking that it is
      # the same kind of object.
      def adopt!(object, holder_id)
        found = lookup(object.pid)
        return holder_id if found && found.noid == holder_id && found.type == object.type

        raise AtlasError.new(object.pid, "Atlas says #{holder_id} holds this pid, but it is not a " \
                                         "#{object.type} Theseus can adopt (#{found.to_h.inspect}).")
      end

      def create_work(item, parent_noid)
        pid = item.object.pid
        work = atlas(pid) do
          @atlas.create_work(parent_noid, idempotency_key: UUID.work_key(pid), handle: item.handle,
                                         legacy_pid: pid)
        end
        noid = work.fetch("id")
        check_legacy_pid!(pid, work)
        check_handle!(pid, noid, work, item.handle, "on create; an Atlas older than 0.6.277 drops it. Not completing")
        atlas(pid, noid) { @atlas.put_mods(noid, item.mods_path) }
        atlas(pid, noid) { @atlas.complete(noid) }
        after = atlas(pid, noid) { @atlas.find_work(noid) }
        check_handle!(pid, noid, after, item.handle, "after complete")
        emit(:completed, pid: pid, noid: noid, handle: item.handle)
        noid
      end

      def check_handle!(pid, noid, work, expected, context)
        return if work["handle"] == expected

        raise AtlasError.new(pid, "Atlas holds handle #{work['handle'].inspect}, not #{expected} (#{context}).",
                             noid: noid)
      end

      # An Atlas older than 0.6.279 ignores legacy_pid, and the object's v1 URL
      # would then never redirect. Stop at the first such create.
      def check_legacy_pid!(pid, created)
        return if created["legacy_pid"] == pid

        raise AtlasError.new(pid, "Atlas holds legacy_pid #{created['legacy_pid'].inspect}, not #{pid}. " \
                                  "An Atlas older than 0.6.279 drops it; stopping before anything else is created.",
                             noid: created.fetch("id"))
      end

      def emit(name, **payload) = @listener.call(Event.new(name, payload))

      def atlas(pid, noid = nil)
        yield
      rescue AtlasGateway::Failure => e
        raise AtlasError.new(pid, e.message, noid: noid)
      end
  end
end
