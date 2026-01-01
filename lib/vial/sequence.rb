# frozen_string_literal: true

module Vial
  class Sequence
    def initialize(start: 1, &block)
      @value = start
      @block = block
    end

    def next_value
      current = @value
      @value += 1
      @block ? @block.call(current) : current
    end
  end

  class SequenceRef
    attr_reader :name

    def initialize(name)
      @name = name.to_sym
    end
  end
end
