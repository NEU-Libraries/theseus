# frozen_string_literal: true

module Theseus
  # One v1 object, as its Solr document describes it.
  class V1Object < Struct.new(:pid, :type, :model, :title, :parent_pid, :handle, keyword_init: true)
    MODELS = { "Community" => :community, "Collection" => :collection, "CoreFile" => :core_file }.freeze

    def self.from_solr(doc)
      model = doc["active_fedora_model_ssi"]
      new(pid: doc.fetch("id"),
          type: MODELS[model],
          model: model,
          title: (doc["full_title_ssi"] || Array(doc["title_tesim"]).first || doc["title_ssi"]).to_s.strip,
          parent_pid: Array(doc["parent_id_tesim"]).first,
          handle: Array(doc["identifier_tesim"]).find { |id| id.include?("hdl.handle.net") })
    end

    # The v2 object_type a run log row names.
    def map_type = type == :core_file ? "work" : type.to_s
  end
end
