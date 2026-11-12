# frozen_string_literal: true

require "digest"

module Theseus
  # RFC 4122 version 5 UUIDs: the same name always gives the same UUID.
  module UUID
    URL_NAMESPACE = "6ba7b811-9dad-11d1-80b4-00c04fd430c8"

    module_function

    def v5(name, namespace = URL_NAMESPACE)
      bytes = Digest::SHA1.digest([namespace.delete("-")].pack("H*") + name).bytes.first(16)
      bytes[6] = (bytes[6] & 0x0f) | 0x50
      bytes[8] = (bytes[8] & 0x3f) | 0x80
      hex = bytes.pack("C*").unpack1("H*")
      [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join("-")
    end

    # The Idempotency-Key for a v1 pid's Work. Atlas keeps keys forever, so
    # every run against the same Atlas replays the first Work.
    def work_key(pid) = v5("info:fedora/#{pid}")
  end
end
