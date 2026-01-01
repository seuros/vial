# frozen_string_literal: true

require_relative 'test_helper'

class YamlEmitterTest < Minitest::Test
  Record = Struct.new(:fixture_label, :attributes)

  def test_emits_common_types
    timestamp = Time.utc(2025, 12, 28, 14, 54, 44, 299_913)
    record = Record.new('one', {
      'raw' => Vial::Erb.new('<%= 1 + 1 %>'),
      'name' => 'Alice',
      'count' => 3,
      'active' => true,
      'missing' => nil,
      'tags' => ['analytics', 'metrics'],
      'published_at' => timestamp
    })

    yaml = Vial::YamlEmitter.new([record]).to_yaml

    assert_includes yaml, "one:"
    assert_includes yaml, "raw: <%= 1 + 1 %>"
    assert_includes yaml, "name: \"Alice\""
    assert_includes yaml, "count: 3"
    assert_includes yaml, "active: true"
    assert_includes yaml, "missing: null"
    assert_includes yaml, "tags:\n    - \"analytics\"\n    - \"metrics\""
    assert_match(/published_at: 2025-12-28T14:54:44/, yaml)
  end
end
