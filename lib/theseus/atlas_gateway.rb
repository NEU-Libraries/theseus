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
  class AtlasGateway
    class Failure < StandardError; end

    def create_community(parent_noid) = guard { AtlasRb::Community.create(parent_noid).fetch("id") }
    def create_collection(parent_noid) = guard { AtlasRb::Collection.create(parent_noid).fetch("id") }

    # Answers the created (or, on an idempotent replay, the original) Work.
    def create_work(collection_noid, idempotency_key:, handle:)
      guard { AtlasRb::Work.create(collection_noid, idempotency_key: idempotency_key, handle: handle) }
    end

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
      rescue AtlasRb::ResourceError => e
        raise Failure, "Atlas answered #{e.status}: #{e.body.to_s[0, 500]}"
      rescue AtlasRb::ForbiddenError => e
        raise Failure, "Atlas answered 403 (#{[e.code, e.action].compact.join(', ')}): #{e.message}"
      rescue AtlasRb::Error, Faraday::Error => e
        raise Failure, "#{e.class}: #{e.message}"
      end
  end
end
