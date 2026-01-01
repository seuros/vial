# frozen_string_literal: true

require 'rails/railtie'

module Vial
  class Railtie < Rails::Railtie
    railtie_name :vial

    rake_tasks do
      load File.expand_path('../tasks/vial.rake', __dir__)
    end
  end
end