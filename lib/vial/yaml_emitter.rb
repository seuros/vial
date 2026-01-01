# frozen_string_literal: true

require 'stringio'

module Vial
  class YamlEmitter
    def initialize(records)
      @records = records
    end

    def to_yaml
      buffer = StringIO.new
      write_to(buffer)
      buffer.string
    end

    def write_to(io)
      @records.each do |record|
        io << "#{record.fixture_label}:\n"
        if record.attributes.empty?
          io << "  {}\n"
          next
        end

        record.attributes.each do |key, value|
          formatted = format_value(value)
          if formatted.is_a?(Array)
            io << "  #{key}:\n"
            formatted.each do |line|
              io << "    #{line}\n"
            end
          else
            io << "  #{key}: #{formatted}\n"
          end
        end
      end
    end

    private

    def format_value(value)
      case value
      in Vial::Erb(source)
        source
      in Time | Date | DateTime | ActiveSupport::TimeWithZone
        format_time(value)
      in TrueClass
        'true'
      in FalseClass
        'false'
      in NilClass
        'null'
      in Numeric
        value.to_s
      in String
        value.inspect
      in Array => array
        format_array(array)
      in Hash => hash
        yaml_block(hash)
      else
        yaml = YAML.dump(value)
        block = normalize_yaml_block(yaml)
        return block if block.length > 1
        block.first
      end
    end

    def yaml_block(value)
      normalize_yaml_block(YAML.dump(value))
    end

    def format_array(array)
      return yaml_block(array) unless array.all? { |item| scalar_value?(item) }

      array.map { |item| "- #{format_scalar(item)}" }
    end

    def scalar_value?(value)
      case value
      in Vial::Erb
        true
      in Time | Date | DateTime | ActiveSupport::TimeWithZone
        true
      in TrueClass | FalseClass | NilClass | Numeric | String
        true
      else
        false
      end
    end

    def format_scalar(value)
      case value
      in Vial::Erb(source)
        source
      in Time | Date | DateTime | ActiveSupport::TimeWithZone
        format_time(value)
      in TrueClass
        'true'
      in FalseClass
        'false'
      in NilClass
        'null'
      in Numeric
        value.to_s
      in String
        value.inspect
      else
        YAML.dump(value).strip
      end
    end

    def normalize_yaml_block(yaml)
      lines = yaml.lines.map(&:rstrip)
      if lines.first&.start_with?('--- ')
        lines[0] = lines.first.sub(/\A---\s*/, '')
      elsif lines.first == '---'
        lines.shift
      end
      lines.pop if lines.last&.start_with?('...')
      lines.reject!(&:empty?)
      lines
    end

    def format_time(value)
      if value.is_a?(Date) && !value.is_a?(Time)
        value.iso8601
      else
        value.iso8601
      end
    end
  end
end
