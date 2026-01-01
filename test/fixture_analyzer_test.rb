# frozen_string_literal: true

require_relative 'test_helper'

class FixtureAnalyzerTest < Minitest::Test
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

  def test_fixture_directive_with_erb_is_parsed
    Object.const_set(:ArticleFixtureModel, Class.new do
      def self.table_name = 'articles'
    end)

    File.write(File.join(@fixtures, 'articles.yml'), <<~YAML)
      _fixture:
        model_class: ArticleFixtureModel
      <% ignored = 1 %>
      one:
        title: "Hello"
    YAML

    analyzer = Vial::FixtureAnalyzer.new
    analyzer.analyze

    info = analyzer.mapped_fixtures['articles']
    assert info
    assert_equal :fixture_directive, info.detection_method
    assert_equal 'ArticleFixtureModel', info.model_name
    assert_equal 'articles', info.table_name
  ensure
    Object.send(:remove_const, :ArticleFixtureModel) if Object.const_defined?(:ArticleFixtureModel)
  end
end
