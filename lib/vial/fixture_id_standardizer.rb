# frozen_string_literal: true

module Vial
  class FixtureIdStandardizer
    Update = Data.define(:file, :model_class, :primary_key, :primary_key_type, :changes)
    Change = Data.define(:label, :primary_key, :current_id, :new_id, :id_type)
    attr_reader :fixture_paths, :updates_needed, :errors

    def initialize(fixture_paths = nil)
      @fixture_paths = Array(fixture_paths || default_fixture_paths)
      @updates_needed = []
      @errors = []
      @analyzer = FixtureAnalyzer.new(fixture_paths)
    end

    def analyze
      @analyzer.analyze
      
      @analyzer.mapped_fixtures.each do |fixture_name, info|
        analyze_fixture_file(info)
      end
      
      self
    end

    def standardize!(dry_run: false)
      analyze if @updates_needed.empty?
      
      @updates_needed.each do |update|
        if dry_run
          puts "Would update: #{update.file}"
          update.changes.each do |change|
            puts "  #{change.label}: #{change.current_id} -> #{change.new_id}"
          end
        else
          apply_updates(update)
        end
      end
    end

    def summary
      pk_type_stats = @analyzer.mapped_fixtures.values.group_by do |info|
        next :unmapped unless info.model_class
        pk = info.model_class.primary_key
        get_primary_key_type(info.model_class, pk) || :unknown
      end.transform_values(&:size)
      
      {
        total_fixtures: @analyzer.mapped_fixtures.size,
        fixtures_needing_updates: @updates_needed.size,
        records_to_update: @updates_needed.sum { |u| u.changes.size },
        primary_key_types: pk_type_stats,
        errors: @errors
      }
    end

    private

    def default_fixture_paths
      fixture_paths = ActiveSupport::TestCase.fixture_paths
      return fixture_paths if fixture_paths && !fixture_paths.empty?

      [Rails.root.join('test/fixtures')]
    end

    def analyze_fixture_file(info)
      return unless info.model_class
      
      file = info.file
      model_class = info.model_class
      
      # Get primary key info
      primary_key = model_class.primary_key
      primary_key_type = get_primary_key_type(model_class, primary_key)
      
      # Skip if no primary key
      return unless primary_key && primary_key_type
      
      # Read and parse fixture file
      content = File.read(file)
      if content.include?('<%')
        @errors << {
          file: file,
          error: 'ERB detected in fixture file; skipping standardization to avoid rewriting dynamic content'
        }
        return
      end

      yaml = YAML.load(content)
      
      return unless yaml.is_a?(Hash)
      
      changes = []
      
      yaml.each do |label, attributes|
        next if label == '_fixture' # Skip meta configuration
        next unless attributes.is_a?(Hash)
        
        # Check if ID needs updating
        current_id = attributes[primary_key] || attributes[primary_key.to_s]
        expected_id = generate_fixture_id(label, primary_key_type)
        
        if should_update_id?(current_id, expected_id, primary_key_type)
          changes << Change.new(
            label: label,
            primary_key: primary_key,
            current_id: current_id,
            new_id: expected_id,
            id_type: primary_key_type
          )
        end
      end
      
      if changes.any?
        @updates_needed << Update.new(
          file: file,
          model_class: model_class,
          primary_key: primary_key,
          primary_key_type: primary_key_type,
          changes: changes
        )
      end
    rescue => e
      @errors << {
        file: file,
        error: e.message,
        backtrace: e.backtrace.first(3)
      }
    end

    def get_primary_key_type(model_class, primary_key)
      return nil unless model_class.connected?
      
      column = model_class.columns_hash[primary_key.to_s]
      return nil unless column
      
      case column.type
      when :uuid
        :uuid
      when :integer, :bigint
        :integer
      when :string
        # String PKs are often manually managed, skip standardization
        :string
      else
        column.type
      end
    rescue
      nil
    end

    def generate_fixture_id(label, primary_key_type)
      case primary_key_type
      when :uuid
        "<%= ActiveRecord::FixtureSet.identify(:#{label}, :uuid) %>"
      when :integer
        "<%= ActiveRecord::FixtureSet.identify(:#{label}) %>"
      when :string
        # Skip string primary keys - they're often manually managed (slugs, etc)
        nil
      else
        nil
      end
    end

    def should_update_id?(current_id, expected_id, primary_key_type)
      return false if expected_id.nil?
      
      # If no current ID, we need to add one
      return true if current_id.nil?
      
      # If current ID is already an ERB expression with identify, it's good
      if current_id.is_a?(String) && current_id.include?('ActiveRecord::FixtureSet.identify')
        # Check if it has the correct format
        if primary_key_type == :uuid
          return !current_id.include?(':uuid')
        else
          return current_id.include?(':uuid')
        end
      end
      
      # If it's a hardcoded value, we need to update it
      true
    end

    def apply_updates(update)
      file = update.file
      content = File.read(file)
      yaml = YAML.load(content)
      
      update.changes.each do |change|
        label = change.label
        if yaml[label]
          # Update or add the primary key
          yaml[label][change.primary_key.to_s] = change.new_id
        end
      end
      
      # Write back to file, preserving YAML formatting as much as possible
      File.write(file, yaml.to_yaml)
      
      puts "Updated: #{file} (#{update.changes.size} records)"
    rescue => e
      @errors << {
        file: file,
        error: "Failed to update: #{e.message}",
        backtrace: e.backtrace.first(3)
      }
    end
  end
end
