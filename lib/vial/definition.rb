# frozen_string_literal: true

module Vial
  class Definition
    Generation = Data.define(:count, :variant, :label_prefix, :source_file, :source_line)
    Record = Data.define(:definition, :fixture_label, :identity_label, :variant_stack, :index, :attributes, :source_file, :source_line)
    SequenceDefinition = Data.define(:start, :block)
    Include = Data.define(:name, :overrides)

    attr_reader :name, :primary_key, :record_type, :id_base, :id_range, :base_attributes, :variant_attributes

    def initialize(name, primary_key: :id, record_type: nil, id_base: nil, id_range: nil, id_type: nil, abstract: false)
      @name = normalize_name(name)
      @primary_key = primary_key.to_s
      @record_type = (record_type ? record_type.to_s : default_record_type(@name))
      @id_base = id_base.nil? ? Vial.config.id_base : id_base
      @id_range = id_range.nil? ? Vial.config.id_range : id_range
      @abstract = !!abstract
      raise ArgumentError, "id_type is not supported; Vial derives deterministic integer IDs" unless id_type.nil?
      raise ArgumentError, "id_range must be positive" unless @id_range.to_i > 0
      @base_attributes = {}
      @variant_attributes = {}
      @generations = []
      @sequence_defs = {}
      @includes = []
      @sequences = nil
    end

    def base(&block)
      @base_attributes = build_attributes(&block)
    end

    def variant(name, &block)
      @variant_attributes[name.to_sym] = build_attributes(&block)
    end

    def include_vial(name, &block)
      overrides = {}
      if block
        builder = IncludeOverrideBuilder.new(self)
        builder.instance_eval(&block)
        overrides = builder.attributes
      end

      @includes << Include.new(name: normalize_name(name), overrides: overrides)
    end

    def generate(*args, **kwargs)
      count, variant, label_prefix = parse_generation_args(*args, **kwargs)
      loc = caller_locations(1, 1).first
      source_file = loc&.absolute_path || loc&.path
      @generations << Generation.new(
        count: count,
        variant: variant,
        label_prefix: label_prefix,
        source_file: source_file,
        source_line: loc&.lineno
      )
    end

    def sequence(name, start: 1, &block)
      if block
        @sequence_defs[name.to_sym] = SequenceDefinition.new(start: start, block: block)
        return
      end

      SequenceRef.new(name)
    end

    def build_records
      @sequences = build_sequences
      base_attrs = resolved_base_attributes
      records = []

      grouped_generations.each do |group|
        variant = group[:variant]
        label = group[:label]
        count = group[:count]
        variant_attrs = variant ? (@variant_attributes[variant] || {}) : {}
        merged_attrs = merge_attributes(base_attrs, variant_attrs)
        static_attrs, dynamic_entries = split_attributes(merged_attrs)
        variant_stack = variant ? [variant] : []
        source_file = group[:source_file]
        source_line = group[:source_line]

        count.times do |offset|
          index = offset + 1
          fixture_label = fixture_label_for(label, index, count)

          attrs = static_attrs.dup
          if dynamic_entries.any?
            context = RecordContext.new(self, label: label, variant: variant, index: index)
            dynamic_entries.each do |key, value|
              attrs[key] = resolve_value(value, context)
            end
          end

          records << Record.new(
            definition: self,
            fixture_label: fixture_label,
            identity_label: label,
            variant_stack: variant_stack,
            index: index,
            attributes: attrs,
            source_file: source_file,
            source_line: source_line
          )
        end
      end

      records
    ensure
      @sequences = nil
    end

    def abstract?
      @abstract
    end

    def explain_id(label:, variant_stack:, index:)
      variants = Array(variant_stack)
      parts = [@name, @record_type, label] + variants + [index]
      normalized = parts.map { |part| normalize_identity_part(part) }.join('::')
      hash_value = Zlib.crc32(normalized)
      {
        tuple: parts,
        normalized: normalized,
        hash: hash_value,
        base: @id_base,
        range: @id_range,
        final: @id_base + (hash_value % @id_range)
      }
    end

    def derive_id(label:, variant_stack:, index:, salt: 0)
      derived_id_for(label: label, variant_stack: variant_stack, index: index, salt: salt)
    end

    def sequence_definitions
      @sequence_defs
    end

    private

    def parse_generation_args(*args, **kwargs)
      if args.length == 0
        raise ArgumentError, 'generate requires a count or variant'
      end

      if args.length == 1
        if args.first.is_a?(Integer)
          count = args.first
          variant = nil
        else
          count = 1
          variant = args.first
        end
      else
        count = args[0]
        variant = args[1]
      end

      label_prefix = kwargs[:label_prefix]
      [count, variant&.to_sym, label_prefix]
    end

    def build_attributes(&block)
      builder = AttributeBuilder.new(self)
      builder.instance_eval(&block) if block
      builder.attributes
    end

    def merge_attributes(base, variant)
      base.merge(variant)
    end

    def grouped_generations
      grouped = {}

      @generations.each do |generation|
        variant = generation.variant
        label = generation.label_prefix || default_label_prefix(variant)
        key = [label, variant]
        entry = grouped[key]
        if entry
          entry[:count] += generation.count
        else
          grouped[key] = {
            count: generation.count,
            source_file: generation.source_file,
            source_line: generation.source_line
          }
        end
      end

      grouped.keys.sort_by { |label, variant| [label.to_s, variant.to_s] }.map do |label, variant|
        entry = grouped[[label, variant]]
        {
          label: label,
          variant: variant,
          count: entry[:count],
          source_file: entry[:source_file],
          source_line: entry[:source_line]
        }
      end
    end

    def fixture_label_for(label, index, count)
      return label.to_s if count == 1
      "#{label}_#{index}"
    end

    def resolved_base_attributes(seen = [])
      if seen.include?(name)
        raise ArgumentError, "Circular include_vial detected: #{(seen + [name]).join(' -> ')}"
      end

      seen << name
      attrs = {}

      @includes.each do |include_entry|
        included = Vial.registry[include_entry.name]
        raise ArgumentError, "Unknown include_vial target: #{include_entry.name}" unless included

        attrs = attrs.merge(included.__send__(:resolved_base_attributes, seen))
        import_sequences_from(included)
        attrs = attrs.merge(include_entry.overrides)
      end

      attrs = attrs.merge(@base_attributes)
      seen.pop
      attrs
    end

    def import_sequences_from(definition)
      definition.sequence_definitions.each do |name, seq_def|
        @sequence_defs[name] ||= seq_def
      end
    end

    def build_sequences
      @sequence_defs.transform_values do |definition|
        Sequence.new(start: definition.start, &definition.block)
      end
    end

    def resolve_values(attributes, label:, variant:, index:)
      context = RecordContext.new(self, label: label, variant: variant, index: index)
      attributes.transform_values do |value|
        resolve_value(value, context)
      end
    end

    def default_label_prefix(variant)
      variant ? variant.to_s : 'base'
    end

    def default_record_type(name)
      base = name.to_s.split('/').last
      ActiveSupport::Inflector.singularize(base)
    end

    def normalize_name(name)
      name.to_s.gsub('__', '/')
    end

    def normalize_identity_part(value)
      value.to_s.downcase
    end

    def derived_id_for(label:, variant_stack:, index:, salt: 0)
      variants = Array(variant_stack)
      parts = [@name, @record_type, label] + variants + [index]
      normalized = parts.map { |part| normalize_identity_part(part) }.join('::')
      normalized = "#{normalized}::#{salt}" if salt.positive?

      hash_value = Zlib.crc32(normalized)
      @id_base + (hash_value % @id_range)
    end

    def resolve_value(value, context)
      case value
      when ExplicitId
        resolved = resolve_value(value.value, context)
        ExplicitId.new(value: resolved, source_file: value.source_file, source_line: value.source_line)
      when SequenceRef
        sequence = @sequences && @sequences[value.name]
        raise ArgumentError, "Unknown sequence: #{value.name}" unless sequence
        sequence.next_value
      when CallableValue
        resolve_value(value.call(context), context)
      else
        value
      end
    end

    def split_attributes(attributes)
      static = {}
      dynamic = []

      attributes.each do |key, value|
        if dynamic_attribute?(value)
          dynamic << [key, value]
        else
          static[key] = value
        end
      end

      [static, dynamic]
    end

    def dynamic_attribute?(value)
      case value
      in ExplicitId(value:)
        dynamic_attribute?(value)
      in SequenceRef | CallableValue
        true
      else
        false
      end
    end

    class AttributeBuilder
      attr_reader :attributes

      def initialize(definition)
        @definition = definition
        @attributes = {}
      end

      def id(value)
        loc = caller_locations(1, 1).first
        source_file = loc&.absolute_path || loc&.path
        @attributes[@definition.primary_key] = ExplicitId.new(
          value: value,
          source_file: source_file,
          source_line: loc&.lineno
        )
      end

      def erb(source)
        Erb.new(source: source)
      end

      def method_missing(name, *args, &block)
        if block
          @attributes[name.to_s] = CallableValue.new(&block)
          return
        end

        if args.length != 1
          raise ArgumentError, "Expected a single value for #{name}"
        end

        if name.to_s == @definition.primary_key
          loc = caller_locations(1, 1).first
          source_file = loc&.absolute_path || loc&.path
          @attributes[name.to_s] = ExplicitId.new(
            value: args.first,
            source_file: source_file,
            source_line: loc&.lineno
          )
        else
          @attributes[name.to_s] = args.first
        end
      end

      def respond_to_missing?(*_args)
        true
      end

      def sequence(name, start: 1, &block)
        @definition.sequence(name, start: start, &block)
      end
    end

    class IncludeOverrideBuilder
      attr_reader :attributes

      def initialize(definition)
        @definition = definition
        @attributes = {}
      end

      def erb(source)
        Erb.new(source: source)
      end

      def id(value)
        loc = caller_locations(1, 1).first
        source_file = loc&.absolute_path || loc&.path
        @attributes[@definition.primary_key] = ExplicitId.new(
          value: value,
          source_file: source_file,
          source_line: loc&.lineno
        )
      end

      def override(name, value = nil, &block)
        if block
          if name.to_s == @definition.primary_key
            loc = caller_locations(1, 1).first
            source_file = loc&.absolute_path || loc&.path
            @attributes[name.to_s] = ExplicitId.new(
              value: CallableValue.new(&block),
              source_file: source_file,
              source_line: loc&.lineno
            )
          else
            @attributes[name.to_s] = CallableValue.new(&block)
          end
          return
        end

        if name.to_s == @definition.primary_key
          loc = caller_locations(1, 1).first
          source_file = loc&.absolute_path || loc&.path
          @attributes[name.to_s] = ExplicitId.new(
            value: value,
            source_file: source_file,
            source_line: loc&.lineno
          )
        else
          @attributes[name.to_s] = value
        end
      end

      def sequence(name, start: 1, &block)
        @definition.sequence(name, start: start, &block)
      end
    end

    class CallableValue
      def initialize(&block)
        @block = block
      end

      def call(context)
        @block.call(context)
      end
    end

    class RecordContext
      attr_reader :label, :variant, :index

      def initialize(definition, label:, variant:, index:)
        @definition = definition
        @label = label
        @variant = variant
        @index = index
      end

      def sequence(name)
        @definition.sequence(name)
      end

      def erb(source)
        Erb.new(source: source)
      end
    end
  end
end
