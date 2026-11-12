# frozen_string_literal: true

require "csv"
require "fileutils"
require "time"

module Theseus
  # The evidence an import leaves: one CSV row per object it created, adopted
  # or replayed, written the moment the step returns. Nothing reads it back.
  # Atlas holds each object's v1 pid, so Atlas, not this file, says what v2
  # already has.
  class RunLog
    FILE = "import_log.csv"
    HEADER = %w[at pid noid object_type outcome].freeze
    TYPES = %w[community collection work].freeze
    OUTCOMES = %w[created adopted replayed].freeze

    attr_reader :path

    def initialize(dir, clock: -> { Time.now.utc })
      @path = File.join(dir, FILE)
      @clock = clock
    end

    def append(pid, noid, object_type, outcome)
      raise ArgumentError, "unknown object_type #{object_type}" unless TYPES.include?(object_type)
      raise ArgumentError, "unknown outcome #{outcome}" unless OUTCOMES.include?(outcome)

      FileUtils.mkdir_p(File.dirname(@path))
      new_file = !File.exist?(@path) || File.zero?(@path)
      File.open(@path, "a") do |file|
        file.write(CSV.generate_line(HEADER)) if new_file
        file.write(CSV.generate_line([@clock.call.iso8601, pid, noid, object_type, outcome]))
        file.flush
      end
    end
  end
end
