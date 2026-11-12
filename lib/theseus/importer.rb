# frozen_string_literal: true

require "fileutils"

module Theseus
  # Imports one v1 pid, and any ancestors v2 lacks, into v2.
  #
  # The run has two halves. The first reads v1 only: it walks the ancestry,
  # fetches every MODS, checks it, and keeps a copy as evidence. The second
  # writes to Atlas, top-down. A finding in the first half stops the run with
  # nothing created.
  class Importer
    Export = Struct.new(:object, :mods_path, :handle)

    def initialize(v1:, atlas:, map:, mods_dir:, root_noid:, out: $stdout)
      @v1 = v1
      @atlas = atlas
      @map = map
      @mods_dir = mods_dir
      @root_noid = root_noid
      @out = out
    end

    def run(pid, into: nil, force: false)
      @map.seed_root!(@root_noid)
      if @map.include?(pid) && !force
        raise FindingError.new(pid, "already_imported",
                               "the map has it as #{@map.noid_for(pid)}; pass --force to re-run")
      end

      objects, parent_noid = plan(pid, into)
      exports = objects.map { |object| export(object) }
      exports.each { |item| parent_noid = create(item, parent_noid) }
      @out.puts("#{pid}: nothing to create") if exports.empty?
    end

    private

      def plan(pid, into)
        if into
          object = V1Object.from_solr(@v1.solr_document(pid))
          raise FindingError.new(pid, "unsupported_model", "#{object.model.inspect} is not a phase 1 type") unless object.type

          return [[object], into]
        end

        # With --force the pid itself is in the map, so it must not end the walk.
        known = ->(candidate) { candidate == pid ? nil : @map.type_for(candidate) }
        chain = Lineage.new(@v1, known: known).walk(pid)
        unless chain.anchor_pid
          top = chain.objects.last.pid
          raise FindingError.new(pid, "unanchored", "the chain ends at #{top}, which the map does not have")
        end

        [chain.top_down, @map.noid_for(chain.anchor_pid)]
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
        Export.new(object, path, handle)
      end

      def create(item, parent_noid)
        object = item.object
        noid = object.type == :core_file ? create_work(item, parent_noid) : create_container(item, parent_noid)
        @map.append(object.pid, noid, object.map_type)
        @out.puts("#{object.pid} -> #{noid} (#{object.map_type}) #{object.title}")
        noid
      end

      def create_container(item, parent_noid)
        object = item.object
        created = atlas(object.pid) do
          if object.type == :community
            @atlas.create_community(parent_noid, legacy_pid: object.pid)
          else
            @atlas.create_collection(parent_noid, legacy_pid: object.pid)
          end
        end
        noid = created.fetch("id")
        check_legacy_pid!(object.pid, created)
        atlas(object.pid, noid) { @atlas.put_mods(noid, item.mods_path) }
        noid
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

      def atlas(pid, noid = nil)
        yield
      rescue AtlasGateway::Failure => e
        raise AtlasError.new(pid, e.message, noid: noid)
      end
  end
end
