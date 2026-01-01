# frozen_string_literal: true

module Vial
  class Config
    attr_accessor :source_paths, :seed, :id_base, :id_range
    attr_writer :output_path

    def initialize
      @source_paths = default_source_paths
      @output_path = nil
      @seed = 1
      @id_base = 0
      @id_range = 90_000
    end
    
    def output_path
      @output_path || default_output_path
    end

    private

    def default_source_paths
      [Rails.root.join('test/vials')]
    end

    def default_output_path
      fixture_paths = Array(ActiveSupport::TestCase.fixture_paths).compact
      return fixture_paths.first if fixture_paths.any?

      Rails.root.join('test/fixtures')
    end
  end
end
