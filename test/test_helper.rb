# frozen_string_literal: true

require 'bundler/setup'
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'pathname'
require 'fileutils'
require 'tmpdir'
require 'yaml'
require 'minitest/autorun'

# Minimal Rails shim for config defaults
module Rails
  def self.root
    Pathname.new(Dir.pwd)
  end
end

require 'vial'

ActiveSupport::TestCase.fixture_paths = [Rails.root.join('test/fixtures')]
