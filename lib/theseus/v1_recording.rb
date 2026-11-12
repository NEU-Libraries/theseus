# frozen_string_literal: true

require "fileutils"
require "json"

module Theseus
  # A recording of v1 responses, so a demo need not depend on live v1. One
  # file per pid and route, holding the response body only: the token is
  # never written. The recordings hold production MODS, so record public
  # objects only, and keep them out of the repo.
  module V1Recording
    ROUTES = { solr_document: "solr.json", mods: "mods.xml" }.freeze

    def self.path(dir, pid, route) = File.join(dir, "#{V1Client.check_pid!(pid).tr(':', '_')}.#{ROUTES.fetch(route)}")
  end

  # Wraps a V1Client and saves each answer it gives (THESEUS_V1_RECORD).
  class V1Recorder
    def initialize(client, dir)
      @client = client
      @dir = dir
    end

    def solr_document(pid)
      @client.solr_document(pid).tap { |doc| save(pid, :solr_document, JSON.pretty_generate(doc)) }
    end

    def mods(pid) = @client.mods(pid).tap { |xml| save(pid, :mods, xml) }

    private

      def save(pid, route, body)
        FileUtils.mkdir_p(@dir)
        File.write(V1Recording.path(@dir, pid, route), body)
      end
  end

  # Answers from a recording, with no token, no network and no pacing
  # (THESEUS_V1_REPLAY). Same two methods as V1Client.
  class V1Replay
    attr_reader :dir

    def initialize(dir)
      raise ConfigError, "THESEUS_V1_REPLAY: #{dir} is not a folder." unless File.directory?(dir)

      @dir = dir
    end

    def solr_document(pid) = JSON.parse(read(pid, :solr_document))
    def mods(pid) = read(pid, :mods)

    private

      def read(pid, route)
        path = V1Recording.path(@dir, pid, route)
        return File.read(path, encoding: "UTF-8") if File.exist?(path)

        raise ConfigError, "The recording in #{@dir} has no #{route} for #{pid} " \
                           "(#{File.basename(path)}). Record it again with THESEUS_V1_RECORD."
      end
  end
end
