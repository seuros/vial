# frozen_string_literal: true

module Vial
  module DSL
    def vial(name, **options, &block)
      Vial.define(name, **options, &block)
    end
  end
end
