# frozen_string_literal: true

require 'bundler/setup'
require 'benchmark/ips'
require 'fileutils'
require 'pathname'
require 'tmpdir'

require 'vial'

unless defined?(Rails)
  module Rails
    def self.root
      Pathname.new(Dir.pwd)
    end
  end
end

VIAL_COUNT = Integer(ENV.fetch('VIAL_BENCH_VIALS', '5'))
RECORDS_PER = Integer(ENV.fetch('VIAL_BENCH_RECORDS', '200'))
WARMUP = Integer(ENV.fetch('VIAL_BENCH_WARMUP', '2'))
TIME = Integer(ENV.fetch('VIAL_BENCH_TIME', '5'))
SEED = Integer(ENV.fetch('VIAL_BENCH_SEED', '123'))
ID_BASE = Integer(ENV.fetch('VIAL_BENCH_ID_BASE', '0'))
ID_RANGE = Integer(ENV.fetch('VIAL_BENCH_ID_RANGE', '90000'))

Dir.mktmpdir('vial-bench') do |dir|
  source_dir = File.join(dir, 'vials')
  output_dir = File.join(dir, 'fixtures')
  FileUtils.mkdir_p(source_dir)

  ActiveSupport::TestCase.fixture_paths = [output_dir]

  VIAL_COUNT.times do |i|
    name = "users_#{i + 1}"
    File.write(File.join(source_dir, "#{name}.vial.rb"), <<~RUBY)
      vial :#{name} do
        sequence(:email) { |j| "user\#{j}-#{i + 1}@example.com" }

        base do
          email sequence(:email)
          active true
          tags ["analytics", "metrics", "events"]
          published_at 5.days.ago
        end

        variant :admin do
          role "admin"
        end

        generate #{RECORDS_PER}
        generate #{RECORDS_PER}, :admin
      end
    RUBY
  end

  Vial.configure do |config|
    config.source_paths = [source_dir]
    config.output_path = output_dir
    config.seed = SEED
    config.id_base = ID_BASE
    config.id_range = ID_RANGE
  end

  Vial.compile!

  Benchmark.ips do |x|
    x.config(time: TIME, warmup: WARMUP)

    x.report('vial:compile') do
      Vial.compile!
    end

    x.compare!
  end
end
