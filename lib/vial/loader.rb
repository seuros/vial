# frozen_string_literal: true

module Vial
  class Loader
    def initialize(path, box:)
      @path = path
      @box = box
    end

    def load
      @box.module_eval(File.read(@path), @path, 1)
    end
  end
end
