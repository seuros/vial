# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "vial"
  require_relative "lib/vial/version"
  spec.version = Vial::VERSION
  spec.authors = ["Abdelkader Boudih"]
  spec.email = ["terminale@gmail.com"]

  spec.summary = "Vial: Fixtures, Reinvented"
  spec.description = "Vial compiles programmable fixture intent into explicit, deterministic fixtures for Rails."
  spec.homepage = "https://github.com/seuros/vial"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/seuros/vial"
  spec.metadata["changelog_uri"] = "https://github.com/seuros/vial/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*", "examples/**/*", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 8.1"

  spec.add_development_dependency "minitest"
  spec.add_development_dependency "rake"
end
