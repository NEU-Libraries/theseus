# frozen_string_literal: true

require "rexml/document"

module Theseus
  # Reads what Theseus needs from a v1 MODS document. It does not change the
  # MODS; the §3.1 double-escape repair is a separate step.
  module Mods
    NAMESPACES = { "mods" => "http://www.loc.gov/mods/v3" }.freeze

    module_function

    # Raises a finding unless the text is a well-formed MODS document.
    def parse!(pid, xml)
      doc = REXML::Document.new(xml)
      root = doc.root
      unless root && root.name == "mods" && root.namespace == NAMESPACES["mods"]
        raise FindingError.new(pid, "invalid_mods", "the document is not MODS")
      end

      doc
    rescue REXML::ParseException => e
      raise FindingError.new(pid, "invalid_mods", "not well-formed XML (#{e.message.lines.first.strip})")
    end

    # The handle in `<identifier type="hdl">`, as `<prefix>/<suffix>`, or nil.
    # Two different handles in one record are a finding.
    def handle(pid, xml)
      doc = parse!(pid, xml)
      values = REXML::XPath.match(doc, "//mods:identifier[@type='hdl']", NAMESPACES)
                           .map { |node| normalize_handle(node.text) }
                           .reject(&:empty?)
                           .uniq
      return values.first if values.size <= 1

      raise FindingError.new(pid, "ambiguous_v1_handle", "the MODS holds #{values.join(', ')}")
    end

    # Strips a resolver host ("http://hdl.handle.net/2047/D1" -> "2047/D1"),
    # as Atlas does with a supplied handle.
    def normalize_handle(value)
      value.to_s.strip.sub(%r{\Ahttps?://[^/]+/}i, "")
    end
  end
end
