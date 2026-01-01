# frozen_string_literal: true

module Vial
  class Registry
    def initialize
      @definitions = []
      @by_name = {}
    end

    def define(name, **options, &block)
      definition = Definition.new(name, **options)
      definition.instance_eval(&block) if block
      @definitions << definition
      @by_name[definition.name] = definition
      definition
    end

    def definitions
      @definitions.dup
    end

    def [](name)
      @by_name[name.to_s]
    end
  end
end
