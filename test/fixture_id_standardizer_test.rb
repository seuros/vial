# frozen_string_literal: true

require_relative 'test_helper'

class FixtureIdStandardizerTest < Minitest::Test
  Column = Struct.new(:type)

  def setup
    @tmpdir = Dir.mktmpdir
    @fixtures = File.join(@tmpdir, 'fixtures')
    FileUtils.mkdir_p(@fixtures)
    @previous_paths = ActiveSupport::TestCase.fixture_paths
    ActiveSupport::TestCase.fixture_paths = [@fixtures]
  end

  def teardown
    ActiveSupport::TestCase.fixture_paths = @previous_paths
    FileUtils.remove_entry(@tmpdir)
  end

  def test_skips_erb_fixture_with_warning
    define_model('ArticleModel')

    file = File.join(@fixtures, 'articles.yml')
    File.write(file, <<~YAML)
      _fixture:
        model_class: ArticleModel
      <% ignored = 1 %>
      one:
        id: 1
        title: "Hello"
    YAML

    standardizer = Vial::FixtureIdStandardizer.new
    standardizer.analyze

    assert_empty standardizer.updates_needed
    assert standardizer.errors.any? { |e| e[:file] == file && e[:error].include?('ERB detected') }
  ensure
    Object.send(:remove_const, :ArticleModel) if Object.const_defined?(:ArticleModel)
  end

  def test_detects_hardcoded_ids
    define_model('LegacyModel')

    file = File.join(@fixtures, 'legacy.yml')
    File.write(file, <<~YAML)
      _fixture:
        model_class: LegacyModel
      one:
        id: 123
        name: "legacy"
    YAML

    standardizer = Vial::FixtureIdStandardizer.new
    standardizer.analyze

    assert_equal 1, standardizer.updates_needed.size
    update = standardizer.updates_needed.first
    assert_equal file, update.file
    assert_equal 1, update.changes.size
    assert_equal '<%= ActiveRecord::FixtureSet.identify(:one) %>', update.changes.first.new_id
  ensure
    Object.send(:remove_const, :LegacyModel) if Object.const_defined?(:LegacyModel)
  end

  def define_model(name)
    model_name = name
    klass = Class.new do
      def self.primary_key = 'id'

      def self.connected?
        true
      end

      def self.columns_hash
        { 'id' => FixtureIdStandardizerTest::Column.new(:integer) }
      end
    end

    klass.define_singleton_method(:table_name) { model_name.to_s.downcase + 's' }
    Object.const_set(name, klass)
  end
end
