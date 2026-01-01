# frozen_string_literal: true

require_relative 'test_helper'

class ExplainIdTest < Minitest::Test
  def test_parse_with_index_and_variants
    vial_name, label, variants, index = Vial::ExplainId.parse('users.admin.eu[3]')

    assert_equal 'users', vial_name
    assert_equal 'admin', label
    assert_equal ['eu'], variants
    assert_equal 3, index
  end

  def test_parse_defaults_index
    vial_name, label, variants, index = Vial::ExplainId.parse('users.admin')

    assert_equal 'users', vial_name
    assert_equal 'admin', label
    assert_equal [], variants
    assert_equal 1, index
  end
end
