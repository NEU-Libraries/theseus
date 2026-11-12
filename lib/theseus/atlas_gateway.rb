# frozen_string_literal: true

require "atlas_rb"

module Theseus
  # The few atlas_rb calls Theseus makes. atlas_rb reads ATLAS_URL and
  # ATLAS_JWT from the environment (BYO-JWT mode).
  #
  # Creates send no MODS. atlas_rb's create(parent, xml_path) writes the MODS
  # inside the same call, and if that write fails the new NOID is lost with
  # the exception. Creating first and writing the MODS second lets Theseus
  # name the shell it left behind.
  #
  # Every create sends the v1 pid as legacy_pid (Atlas 0.6.279, atlas_rb
  # 1.29.5). Atlas lets one object hold a pid, so the pid is also how Theseus
  # asks whether v2 already has something.
  class AtlasGateway
    class Failure < StandardError; end

    # Atlas refused a create because another object already holds the pid.
    class PidTaken < Failure
      attr_reader :holder_id

      def initialize(message, holder_id)
        @holder_id = holder_id
        super(message)
      end
    end

    # Each create answers the new object's JSON, legacy_pid included, so the
    # caller can confirm that Atlas kept the pid.
    def create_community(parent_noid, legacy_pid:)
      guard { AtlasRb::Community.create(parent_noid, legacy_pid: legacy_pid) }
    end

    def create_collection(parent_noid, legacy_pid:)
      guard { AtlasRb::Collection.create(parent_noid, legacy_pid: legacy_pid) }
    end

    # Answers the created (or, on an idempotent replay, the original) Work.
    def create_work(collection_noid, idempotency_key:, handle:, legacy_pid:)
      guard do
        AtlasRb::Work.create(collection_noid, idempotency_key: idempotency_key, handle: handle,
                                              legacy_pid: legacy_pid)
      end
    end

    # The object that holds a v1 pid: `id`, `type` ("Community", "Collection"
    # or "Work") and `tombstoned`. nil when nothing holds it.
    def find_by_legacy_pid(pid) = guard { AtlasRb::Resource.find_by_legacy_pid(pid) }

    def put_mods(noid, path) = guard { AtlasRb::Resource.put_mods(noid, path) }

    def complete(noid)
      guard do
        response = AtlasRb::Work.complete(noid)
        raise Failure, "complete answered #{response.status}" unless response.success?

        response
      end
    end

    def find_work(noid) = guard { AtlasRb::Work.find(noid) }

    private

      def guard
        yield
      rescue AtlasRb::LegacyPidError => e
        if e.code == "legacy_pid_taken"
          raise PidTaken.new("Atlas answered 409: #{e.holder_id} already holds this pid", e.holder_id)
        end

        raise Failure, "Atlas answered #{e.status} (#{e.code}): #{e.body.to_s[0, 500]}"
      rescue AtlasRb::ResourceError => e
        raise Failure, "Atlas answered #{e.status}: #{e.body.to_s[0, 500]}"
      rescue AtlasRb::ForbiddenError => e
        if e.action == "supply_legacy_pid"
          raise ConfigError, "Atlas will not record a v1 pid for this token. ATLAS_JWT must be an admin's."
        end

        raise Failure, "Atlas answered 403 (#{[e.code, e.action].compact.join(', ')}): #{e.message}"
      rescue AtlasRb::Error, Faraday::Error => e
        raise Failure, "#{e.class}: #{e.message}"
      end
  end
end
