#!/usr/bin/env ruby
# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'benchmark'

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'vial'

Scenario = Data.define(:vials, :variants, :per_variant)

SCENARIOS = {
  small: Scenario.new(vials: 5, variants: 2, per_variant: 200),
  medium: Scenario.new(vials: 20, variants: 3, per_variant: 500),
  large: Scenario.new(vials: 50, variants: 4, per_variant: 1000)
}.freeze

options = {
  scenario: :medium,
  iterations: 3,
  id_range: 900_000,
  seed: 1
}

args = ARGV.dup
until args.empty?
  case args
  in ['--scenario', value, *rest]
    options[:scenario] = value.to_sym
    args = rest
  in ['--iterations', value, *rest]
    options[:iterations] = value.to_i
    args = rest
  in ['--vials', value, *rest]
    options[:vials] = value.to_i
    args = rest
  in ['--variants', value, *rest]
    options[:variants] = value.to_i
    args = rest
  in ['--per-variant', value, *rest]
    options[:per_variant] = value.to_i
    args = rest
  in ['--id-range', value, *rest]
    options[:id_range] = value.to_i
    args = rest
  in ['--seed', value, *rest]
    options[:seed] = value.to_i
    args = rest
  in ['--help', *]
    puts <<~USAGE
      Usage: script/bench.rb [options]
        --scenario small|medium|large
        --iterations N
        --vials N
        --variants N
        --per-variant N
        --id-range N
        --seed N
    USAGE
    exit 0
  else
    warn "Unknown arguments: #{args.join(' ')}"
    exit 1
  end
end

scenario = SCENARIOS.fetch(options[:scenario])
config = scenario.to_h.merge(options)
config[:vials] ||= scenario.vials
config[:variants] ||= scenario.variants
config[:per_variant] ||= scenario.per_variant

records_per_vial = config[:variants] * config[:per_variant]
total_records = config[:vials] * records_per_vial

Dir.mktmpdir('vial-bench') do |dir|
  source_dir = File.join(dir, 'vials')
  output_dir = File.join(dir, 'fixtures')
  FileUtils.mkdir_p(source_dir)
  FileUtils.mkdir_p(output_dir)

  config[:vials].times do |index|
    vial_name = "bench_users_#{index + 1}"
    file_path = File.join(source_dir, "#{vial_name}.vial.rb")
    id_base = (index + 1) * 1_000_000

    variant_defs = (1..config[:variants]).map do |variant_index|
      <<~RUBY
        variant :v#{variant_index} do
          role "v#{variant_index}"
        end
      RUBY
    end.join("\n")

    generate_defs = (1..config[:variants]).map do |variant_index|
      "  generate #{config[:per_variant]}, :v#{variant_index}"
    end.join("\n")

    File.write(file_path, <<~RUBY)
      # frozen_string_literal: true

      vial :#{vial_name}, id_base: #{id_base}, id_range: #{config[:id_range]} do
        base do
          active true
          email sequence(:email)
        end

        sequence(:email) { |i| "#{vial_name}_#{index + 1}_\#{i}@test.local" }

      #{variant_defs.rstrip}

      #{generate_defs}
      end
    RUBY
  end

  Vial.configure do |cfg|
    cfg.source_paths = [source_dir]
    cfg.output_path = output_dir
    cfg.seed = config[:seed]
    cfg.id_range = config[:id_range]
  end

  times = []
  allocations = []

  config[:iterations].times do
    GC.start
    before_alloc = GC.stat(:total_allocated_objects)
    elapsed = Benchmark.realtime do
      Vial.compile!(source_paths: [source_dir], output_path: output_dir, seed: config[:seed])
    end
    after_alloc = GC.stat(:total_allocated_objects)

    times << elapsed
    allocations << (after_alloc - before_alloc)
  end

  min = times.min
  max = times.max
  avg = times.sum / times.size
  avg_alloc = allocations.sum / allocations.size

  Result = Data.define(
    :scenario,
    :vials,
    :variants,
    :per_variant,
    :records_per_vial,
    :total_records,
    :iterations,
    :min,
    :avg,
    :max,
    :avg_alloc
  )

  result = Result.new(
    scenario: options[:scenario],
    vials: config[:vials],
    variants: config[:variants],
    per_variant: config[:per_variant],
    records_per_vial: records_per_vial,
    total_records: total_records,
    iterations: config[:iterations],
    min: min,
    avg: avg,
    max: max,
    avg_alloc: avg_alloc
  )

  puts "Scenario: #{result.scenario}"
  puts "Vials: #{result.vials}, Variants: #{result.variants}, Per variant: #{result.per_variant}"
  puts "Records per vial: #{result.records_per_vial}, Total records: #{result.total_records}"
  puts "Iterations: #{result.iterations}"
  puts format('Time (s) min/avg/max: %.4f / %.4f / %.4f', result.min, result.avg, result.max)
  puts format('Allocated objects avg: %.0f', result.avg_alloc)
end
