# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'set'
require 'yaml'
require 'zlib'
require 'time'
require 'date'
require 'active_record'
require 'active_support/inflector'
require 'active_support/test_case'
require 'active_support/time'
require 'vial/version'

unless ActiveSupport::TestCase.respond_to?(:fixture_paths)
  ActiveSupport::TestCase.singleton_class.attr_accessor :fixture_paths
end

begin
  require 'vial/railtie'
rescue LoadError
  # Rails is optional for the core compiler; tasks load via Railtie when present.
end
require 'vial/config'
require 'vial/explicit_id'
require 'vial/erb'
require 'vial/sequence'
require 'vial/definition'
require 'vial/registry'
require 'vial/dsl'
require 'vial/loader'
require 'vial/explain_id'
require 'vial/yaml_emitter'
require 'vial/compiler'
require 'vial/validator'
require 'vial/fixture_analyzer'
require 'vial/fixture_id_standardizer'

module Vial
  def self.version
    VERSION
  end

  def self.config
    @config ||= Config.new
  end

  def self.configure
    yield(config) if block_given?
    config
  end

  def self.registry
    @registry ||= Registry.new
  end

  def self.last_loaded_files
    @last_loaded_files ||= []
  end

  def self.reset_registry!
    @registry = Registry.new
  end

  def self.define(name, **options, &block)
    registry.define(name, **options, &block)
  end

  def self.compile!(dry_run: false, only: nil, **options)
    Compiler.new(config: config, **options).compile!(dry_run: dry_run, only: only)
  end

  def self.clean!(**options)
    Compiler.new(config: config, **options).clean!
  end

  def self.build_box
    box = if defined?(Ruby::Box) && ENV['RUBY_BOX'] == '1'
      Ruby::Box.new
    else
      Module.new
    end

    host_vial = self
    box.singleton_class.define_method(:vial) do |name, **options, &block|
      host_vial.define(name, **options, &block)
    end

    box
  end

  def self.load_sources!(source_paths: config.source_paths)
    reset_registry!
    @last_loaded_files = []
    box = build_box
    Array(source_paths).each do |path|
      next unless File.directory?(path)

      Dir[File.join(path, '**', '*.vial.rb')].sort.each do |file|
        @last_loaded_files << file
        Loader.new(file, box: box).load
      end
    end

    registry
  end
end
