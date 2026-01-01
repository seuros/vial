# frozen_string_literal: true

module Vial
  module ExplainId
    module_function

    def parse(query)
      query = query.to_s.strip
      match = query.match(/\[(\d+)\]\s*\z/)
      index = match ? match[1].to_i : 1
      query = query.sub(/\[(\d+)\]\s*\z/, '')

      parts = query.split('.').map(&:strip).reject(&:empty?)
      raise ArgumentError, "Invalid explain_id query: #{query}" if parts.length < 2

      vial_name = normalize_vial_name(parts.shift)
      label = parts.shift
      variants = parts

      [vial_name, label, variants, index]
    end

    def normalize_vial_name(name)
      name.to_s.gsub('__', '/')
    end
  end
end
