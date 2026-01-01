# frozen_string_literal: true

require_relative 'test_helper'

class CompilerTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @vials = File.join(@tmpdir, 'vials')
    @fixtures = File.join(@tmpdir, 'fixtures')
    FileUtils.mkdir_p(@vials)
    @previous_fixture_paths = ActiveSupport::TestCase.fixture_paths
    ActiveSupport::TestCase.fixture_paths = [@fixtures]

    Vial.configure do |config|
      config.source_paths = [@vials]
      config.output_path = @fixtures
      config.seed = 123
    end
  end

  def teardown
    ActiveSupport::TestCase.fixture_paths = @previous_fixture_paths
    FileUtils.remove_entry(@tmpdir)
    Vial.reset_registry!
  end

  def test_compile_writes_fixtures_with_sequences
    File.write(File.join(@vials, 'users.vial.rb'), <<~'RUBY')
      vial :users do
        sequence(:email) { |i| "user#{i}@example.com" }

        base do
          email sequence(:email)
          active true
        end

        generate 2
      end
    RUBY

    Vial.compile!

    data = YAML.load_file(File.join(@fixtures, 'users.yml'))
    assert_equal ['base_1', 'base_2'], data.keys
    assert_equal 'user1@example.com', data['base_1']['email']
    assert_equal true, data['base_1']['active']
    assert data['base_1']['id'].is_a?(Integer)
  end

  def test_compile_is_deterministic_with_seed
    File.write(File.join(@vials, 'tokens.vial.rb'), <<~RUBY)
      vial :tokens do
        base do
          token { rand(1..999_999) }
        end

        generate 2
      end
    RUBY

    Vial.compile!
    first = File.read(File.join(@fixtures, 'tokens.yml'))

    Vial.compile!
    second = File.read(File.join(@fixtures, 'tokens.yml'))

    assert_equal first, second
  end

  def test_dry_run_does_not_write_files
    File.write(File.join(@vials, 'tokens.vial.rb'), <<~RUBY)
      vial :tokens do
        base do
          value { rand(1..10) }
        end

        generate 1
      end
    RUBY

    result = Vial.compile!(dry_run: true)

    assert_equal :dry_run, result.status
    refute File.exist?(File.join(@fixtures, 'tokens.yml'))
    refute File.exist?(File.join(@fixtures, '.vial_manifest.yml'))
  end

  def test_clean_removes_stale_fixtures_from_manifest
    vial_file = File.join(@vials, 'users.vial.rb')
    File.write(vial_file, <<~RUBY)
      vial :users do
        base do
          email "user@example.com"
        end

        generate 1
      end
    RUBY

    Vial.compile!
    fixture_path = File.join(@fixtures, 'users.yml')
    assert File.exist?(fixture_path)

    File.delete(vial_file)
    Vial.clean!

    refute File.exist?(fixture_path)
  end
end
