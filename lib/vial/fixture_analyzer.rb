# frozen_string_literal: true

require 'erb'

module Vial
  class FixtureAnalyzer
    FixtureInfo = Data.define(:file, :fixture_name, :model_class, :model_name, :table_name, :detection_method)

    attr_reader :fixture_paths, :model_mappings, :errors

    def initialize(fixture_paths = nil)
      @fixture_paths = Array(fixture_paths || default_fixture_paths)
      @model_mappings = {}
      @errors = []
      @fixture_class_names = {}
    end

    def analyze
      load_fixture_class_mappings
      
      @fixture_paths.each do |path|
        analyze_path(path)
      end
      
      self
    end

    def summary
      {
        total_fixtures: @model_mappings.size,
        mapped_fixtures: @model_mappings.count { |_, v| v.model_class.present? },
        unmapped_fixtures: @model_mappings.count { |_, v| v.model_class.nil? },
        errors: @errors
      }
    end

    def mapped_fixtures
      @model_mappings.select { |_, v| v.model_class.present? }
    end

    def unmapped_fixtures
      @model_mappings.select { |_, v| v.model_class.nil? }
    end

    def fixture_for_model(model_name)
      model_class = model_name.is_a?(Class) ? model_name : model_name.to_s.safe_constantize
      return nil unless model_class
      
      @model_mappings.select { |_, v| v.model_class == model_class }
    end

    private

    def default_fixture_paths
      fixture_paths = ActiveSupport::TestCase.fixture_paths
      return fixture_paths if fixture_paths && !fixture_paths.empty?

      [Rails.root.join('test/fixtures')]
    end

    def load_fixture_class_mappings
      if ActiveSupport::TestCase.respond_to?(:fixture_class_names)
        @fixture_class_names = ActiveSupport::TestCase.fixture_class_names || {}
      end
    end

    def analyze_path(path)
      return unless File.directory?(path)
      
      Dir[File.join(path, '**/*.yml')].each do |file|
        analyze_fixture_file(file, path)
      end
    end

    def analyze_fixture_file(file, base_path)
      relative_path = file.sub(/^#{Regexp.escape(base_path.to_s)}\//, '').sub(/\.yml$/, '')
      fixture_name = relative_path
      
      # Skip special fixtures
      return if fixture_name == 'DEFAULTS' || fixture_name.start_with?('_')
      
      model_class = determine_model_class(file, fixture_name)
      
      model_name = model_class.is_a?(Class) ? model_class.name : model_class
      table_name = model_class.is_a?(Class) ? model_class.table_name : nil

      @model_mappings[fixture_name] = FixtureInfo.new(
        file: file,
        fixture_name: fixture_name,
        model_class: model_class,
        model_name: model_name,
        table_name: table_name,
        detection_method: @detection_method
      )
    rescue => e
      @errors << {
        file: file,
        error: e.message,
        backtrace: e.backtrace.first(3)
      }
    end

    def determine_model_class(file, fixture_name)
      # 1. Check for _fixture directive in YAML
      if model_class = check_fixture_directive(file)
        @detection_method = :fixture_directive
        return model_class
      end
      
      # 2. Check set_fixture_class mappings
      if model_class = check_fixture_class_mapping(fixture_name)
        @detection_method = :set_fixture_class
        return model_class
      end
      
      # 3. Infer from fixture path
      if model_class = infer_from_path(fixture_name)
        @detection_method = :path_inference
        return model_class
      end
      
      @detection_method = :none
      nil
    end

    def check_fixture_directive(file)
      yaml = load_fixture_yaml(file)
      
      return nil unless yaml.is_a?(Hash)
      
      if fixture_config = yaml['_fixture']
        if model_class_name = fixture_config['model_class']
          # Try to constantize, but if it fails, still return the string
          # so we know the fixture has a directive
          model_class = model_class_name.safe_constantize
          return model_class || model_class_name
        end
      end
      
      nil
    rescue => e
      @errors << {
        file: file,
        error: "Failed to parse fixture YAML: #{e.message}",
        backtrace: e.backtrace.first(3)
      }
      nil
    end

    def load_fixture_yaml(file)
      content = File.read(file)
      content = ERB.new(content).result if content.include?('<%')
      YAML.safe_load(
        content,
        permitted_classes: permitted_yaml_classes,
        permitted_symbols: [],
        aliases: true
      )
    end

    def permitted_yaml_classes
      [Time, Date, DateTime, ActiveSupport::TimeWithZone]
    end

    def check_fixture_class_mapping(fixture_name)
      # Check exact match
      if class_name = @fixture_class_names[fixture_name]
        return class_name.is_a?(Class) ? class_name : class_name.to_s.safe_constantize
      end
      
      # Check with slashes replaced by underscores (Rails convention)
      underscore_name = fixture_name.tr('/', '_')
      if class_name = @fixture_class_names[underscore_name]
        return class_name.is_a?(Class) ? class_name : class_name.to_s.safe_constantize
      end
      
      nil
    end

    def infer_from_path(fixture_name)
      # Handle namespaced fixtures (e.g., 'platform/countries')
      parts = fixture_name.split('/')
      
      # Try various naming conventions
      candidates = [
        # Exact path as namespace (platform/countries -> Platform::Country)
        parts.map(&:singularize).map(&:camelize).join('::'),
        # Last part only (platform/countries -> Country)
        parts.last.singularize.camelize,
        # With Model suffix (platform/countries -> Platform::CountryModel)
        parts.map(&:singularize).map(&:camelize).join('::') + 'Model',
        # Pluralized namespace (platforms/country -> Platforms::Country)
        parts[0..-2].map(&:camelize).join('::') + '::' + parts.last.singularize.camelize
      ]
      
      # Add table name prefix handling
      prefix = ActiveRecord::Base.table_name_prefix
      if prefix.present? && fixture_name.start_with?(prefix)
        unprefixed = fixture_name.sub(/^#{Regexp.escape(prefix)}/, '')
        candidates << unprefixed.singularize.camelize
      end
      
      # Try each candidate
      candidates.each do |candidate|
        next if candidate.blank?
        
        if model_class = candidate.safe_constantize
          # Verify it's an ActiveRecord model
          if model_class < ActiveRecord::Base
            # Additional verification: check if table name matches
            expected_table = fixture_name.tr('/', '_')
            if model_class.table_name == expected_table
              return model_class
            end
          end
        end
      end
      
      nil
    end
  end
end
