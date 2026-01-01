# frozen_string_literal: true

module Vial
  class Compiler
    CompileResult = Data.define(:status, :files, :output_path)
    CleanResult = Data.define(:status, :removed)
    attr_reader :config, :source_paths, :output_path, :seed

    def initialize(config:, source_paths: nil, output_path: nil, seed: nil)
      @config = config
      @source_paths = Array(source_paths || config.source_paths)
      @output_path = output_path || config.output_path
      @seed = seed || config.seed
    end

    def compile!(dry_run: false, only: nil)
      previous_seed = srand(@seed)
      Vial.load_sources!(source_paths: @source_paths)

      definitions = Vial.registry.definitions
      if definitions.empty?
        warn "Vial: no vial definitions found in #{@source_paths.join(', ')}"
        return CompileResult.new(status: :no_definitions, files: [], output_path: @output_path.to_s)
      end

      selected_definitions = filter_definitions(definitions, only)
      if selected_definitions.empty?
        warn "Vial: no matching vials to compile"
        return CompileResult.new(status: :no_definitions, files: [], output_path: @output_path.to_s)
      end

      records_by_definition = definitions.each_with_object([]) do |definition, entries|
        next if definition.abstract?
        entries << { definition: definition, records: definition.build_records }
      end

      total_records = records_by_definition.sum { |entry| entry[:records].size }
      if total_records == 0
        warn "Vial: no records generated (all definitions are abstract or missing generate calls)"
        return CompileResult.new(status: :no_records, files: [], output_path: @output_path.to_s)
      end

      Validator.new(records_by_definition).validate!

      warn_if_output_path_unconfigured

      selected_names = selected_definitions.map(&:name).to_set
      selected_records = records_by_definition.select { |entry| selected_names.include?(entry[:definition].name) }
      files_to_write = selected_records.map { |entry| fixture_path_for(entry[:definition]) }

      if dry_run
        return CompileResult.new(status: :dry_run, files: files_to_write, output_path: @output_path.to_s)
      end

      selected_records.each do |entry|
        write_fixture(entry[:definition], entry[:records])
      end

      write_manifest(expected_fixture_paths(definitions))

      CompileResult.new(status: :compiled, files: files_to_write, output_path: @output_path.to_s)
    ensure
      srand(previous_seed) unless previous_seed.nil?
    end

    def clean!
      Vial.load_sources!(source_paths: @source_paths)
      definitions = Vial.registry.definitions
      expected = expected_fixture_paths(definitions)
      manifest = read_manifest

      if manifest.empty?
        warn "Vial: no manifest found; nothing to clean"
        return CleanResult.new(status: :no_manifest, removed: [])
      end

      removed = []
      manifest.each do |relative_path|
        next if expected.include?(relative_path)

        file_path = File.join(@output_path.to_s, relative_path)
        next unless File.exist?(file_path)

        File.delete(file_path)
        removed << file_path
      end

      write_manifest(expected)
      CleanResult.new(status: :cleaned, removed: removed)
    end

    private

    def write_fixture(definition, records)
      file_path = File.join(@output_path.to_s, "#{definition.name}.yml")
      FileUtils.mkdir_p(File.dirname(file_path))

      emitter = YamlEmitter.new(records)
      File.open(file_path, 'w') do |file|
        emitter.write_to(file)
      end
    end

    def fixture_path_for(definition)
      File.join(@output_path.to_s, "#{definition.name}.yml")
    end

    def expected_fixture_paths(definitions)
      base = Pathname.new(@output_path.to_s)
      definitions.reject(&:abstract?).map do |definition|
        Pathname.new(fixture_path_for(definition)).relative_path_from(base).to_s
      end
    end

    def manifest_path
      File.join(@output_path.to_s, '.vial_manifest.yml')
    end

    def write_manifest(expected_paths)
      FileUtils.mkdir_p(@output_path.to_s)
      File.write(manifest_path, YAML.dump(expected_paths))
    end

    def read_manifest
      return [] unless File.exist?(manifest_path)

      data = YAML.load_file(manifest_path)
      data.is_a?(Array) ? data : []
    rescue
      []
    end

    def filter_definitions(definitions, only)
      filtered = definitions.reject(&:abstract?)
      return filtered if only.nil?

      names = Array(only).flat_map { |name| name.to_s.split(',') }
      names = names.map(&:strip).reject(&:empty?).map { |name| name.tr('__', '/') }

      filtered.select { |definition| names.include?(definition.name) }
    end

    def warn_if_output_path_unconfigured
      fixture_paths = Array(ActiveSupport::TestCase.fixture_paths).compact.map { |path| File.expand_path(path.to_s) }
      return if fixture_paths.empty?

      output = File.expand_path(@output_path.to_s)

      return if fixture_paths.any? { |path| output == path || output.start_with?(path + File::SEPARATOR) }

      warn "Vial: output_path (#{@output_path}) is not inside fixture_paths"
    end
  end
end
