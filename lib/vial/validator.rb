# frozen_string_literal: true

module Vial
  class ValidationError < StandardError
    attr_reader :type, :details

    def initialize(type, details)
      @type = type
      @details = details
      super(build_message)
    end

    private

    def build_message
      (["#{type}:"] + details.map { |detail| "  #{detail}" }).join("\n")
    end
  end

  class Validator
    MAX_DERIVED_SALTS = 3

    def initialize(records_by_definition)
      @records_by_definition = records_by_definition
    end

    def validate!
      validate_duplicate_labels!
      assign_and_validate_ids!
      true
    end

    private

    def validate_duplicate_labels!
      @records_by_definition.each do |entry|
        definition = entry[:definition]
        records = entry[:records]
        label_map = {}

        records.each do |record|
          label = record.identity_label
          variant_key = normalize_variant_key(record.variant_stack)
          existing = label_map[label]

          if existing && existing[:variant_key] != variant_key
            raise ValidationError.new(
              'DuplicateLabel',
              [
                "vial: #{definition.name}",
                "record_type: #{definition.record_type}",
                "label: #{label}",
                "first: #{format_source(existing[:source_file], existing[:source_line])} (variant: #{existing[:variant_label]})",
                "second: #{format_source(record.source_file, record.source_line)} (variant: #{format_variant(record.variant_stack)})"
              ]
            )
          end

          label_map[label] ||= {
            variant_key: variant_key,
            variant_label: format_variant(record.variant_stack),
            source_file: record.source_file,
            source_line: record.source_line
          }
        end
      end
    end

    def assign_and_validate_ids!
      used_ids = {}
      all_records.each do |record|
        explicit = explicit_id_for(record)
        next unless explicit

        id_value = explicit[:value]
        if (existing = used_ids[id_value])
          raise ValidationError.new(
            'ExplicitIDCollision',
            [
              "ID: #{id_value.inspect}",
              record_descriptor(existing[:record], existing[:source_file], existing[:source_line]),
              record_descriptor(record, explicit[:source_file], explicit[:source_line])
            ]
          )
        end

        record.attributes[record.definition.primary_key] = id_value
        used_ids[id_value] = { explicit: true, record: record, source_file: explicit[:source_file], source_line: explicit[:source_line] }
      end

      derived_records = all_records.reject { |record| record.attributes.key?(record.definition.primary_key) }
      derived_records.sort_by { |record| sort_key(record) }.each do |record|
        assign_derived_id!(record, used_ids)
      end
    end

    def assign_derived_id!(record, used_ids)
      attempts = 0
      last_collision = nil

      while attempts < MAX_DERIVED_SALTS
        id_value = record.definition.derive_id(
          label: record.identity_label,
          variant_stack: record.variant_stack,
          index: record.index,
          salt: attempts
        )

        existing = used_ids[id_value]
        if existing.nil?
          record.attributes[record.definition.primary_key] = id_value
          used_ids[id_value] = { explicit: false, record: record }
          return
        end

        if existing[:explicit]
          raise ValidationError.new(
            'DerivedIDCollision',
            [
              "ID: #{id_value.inspect}",
              "derived: #{record_descriptor(record, record.source_file, record.source_line)}",
              "explicit: #{record_descriptor(existing[:record], existing[:source_file], existing[:source_line])}"
            ]
          )
        end

        last_collision = { id: id_value, existing: existing }
        attempts += 1
      end

      raise ValidationError.new(
        'DerivedIDCollision',
        [
          "ID: #{last_collision ? last_collision[:id].inspect : 'unknown'}",
          "derived: #{record_descriptor(record, record.source_file, record.source_line)}",
          (last_collision ? "existing: #{record_descriptor(last_collision[:existing][:record], last_collision[:existing][:record].source_file, last_collision[:existing][:record].source_line)}" : nil),
          "vial: #{record.definition.name}",
          "record_type: #{record.definition.record_type}",
          "source: #{format_source(record.source_file, record.source_line)}"
        ].compact
      )
    end

    def explicit_id_for(record)
      primary_key = record.definition.primary_key
      return nil unless record.attributes.key?(primary_key)

      value = record.attributes[primary_key]
      case value
      in ExplicitId(value:, source_file:, source_line:)
        { value: value, source_file: source_file, source_line: source_line }
      else
        { value: value, source_file: record.source_file, source_line: record.source_line }
      end
    end

    def all_records
      @all_records ||= @records_by_definition.flat_map { |entry| entry[:records] }
    end

    def sort_key(record)
      [
        record.definition.name.to_s.downcase,
        record.definition.record_type.to_s.downcase,
        record.identity_label.to_s.downcase,
        normalize_variant_key(record.variant_stack),
        record.index
      ]
    end

    def normalize_variant_key(variant_stack)
      Array(variant_stack).map(&:to_s).join('::').downcase
    end

    def format_variant(variant_stack)
      stack = Array(variant_stack).map(&:to_s)
      return 'base' if stack.empty?
      stack.join('.')
    end

    def record_descriptor(record, source_file, source_line)
      variant = format_variant(record.variant_stack)
      label = record.identity_label
      "#{format_source(source_file, source_line)} (vial: #{record.definition.name}, record_type: #{record.definition.record_type}, label: #{label}, variant: #{variant}, index: #{record.index})"
    end

    def format_source(source_file, source_line)
      return 'unknown' unless source_file
      source_line ? "#{source_file}:#{source_line}" : source_file
    end
  end
end
