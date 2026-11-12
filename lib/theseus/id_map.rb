# frozen_string_literal: true

require "csv"
require "fileutils"

module Theseus
  # The pid -> NOID CSV that `rake legacy:load` reads. Append-only: a row is
  # written, flushed and synced the moment its create returns, because
  # Collection.create and Community.create take no idempotency key. A crash
  # before the row lands would make the next run create the container again.
  # When a pid appears twice (a --force re-run), the last row wins.
  class IdMap
    HEADER = %w[pid noid object_type].freeze
    TYPES = { "community" => :community, "collection" => :collection, "work" => :core_file }.freeze
    ROOT_PID = "neu:1"

    Row = Struct.new(:pid, :noid, :object_type)

    def initialize(path)
      @path = path
      @rows = {}
      load_rows if File.exist?(path)
    end

    def include?(pid) = @rows.key?(pid)
    def noid_for(pid) = @rows[pid]&.noid
    def type_for(pid) = @rows[pid] && TYPES.fetch(@rows[pid].object_type)

    # Makes the map name V2_ROOT as neu:1. A map that names another root is
    # left over from before a reset, and every NOID in it is gone.
    def seed_root!(noid)
      row = @rows[ROOT_PID]
      return append(ROOT_PID, noid, "community") unless row
      return if row.noid == noid

      raise ConfigError, "#{@path} has neu:1 as #{row.noid}, but V2_ROOT is #{noid}. " \
                         "After a reset, start a new map."
    end

    def append(pid, noid, object_type)
      raise ArgumentError, "unknown object_type #{object_type}" unless TYPES.key?(object_type)

      FileUtils.mkdir_p(File.dirname(@path))
      new_file = !File.exist?(@path) || File.zero?(@path)
      File.open(@path, "a") do |file|
        file.write(CSV.generate_line(HEADER)) if new_file
        file.write(CSV.generate_line([pid, noid, object_type]))
        file.flush
        file.fsync
      end
      @rows[pid] = Row.new(pid, noid, object_type)
    end

    private

      def load_rows
        CSV.foreach(@path, headers: true) do |line|
          unless TYPES.key?(line["object_type"])
            raise ConfigError, "#{@path}: unknown object_type #{line['object_type'].inspect}"
          end

          @rows[line["pid"]] = Row.new(line["pid"], line["noid"], line["object_type"])
        end
      end
  end
end
