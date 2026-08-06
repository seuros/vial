# frozen_string_literal: true

require_relative 'test_helper'

class ValidatorTest < Minitest::Test
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

  def test_explicit_ids_may_repeat_across_record_types
    File.write(File.join(@vials, 'users.vial.rb'), <<~'RUBY')
      vial :users do
        sequence(:id) { |i| i }

        base do
          id sequence(:id)
          name "user"
        end

        generate 3
      end
    RUBY
    File.write(File.join(@vials, 'posts.vial.rb'), <<~'RUBY')
      vial :posts do
        sequence(:id) { |i| i }

        base do
          id sequence(:id)
          title "post"
        end

        generate 3
      end
    RUBY

    Vial.compile!

    users = YAML.load_file(File.join(@fixtures, 'users.yml'))
    posts = YAML.load_file(File.join(@fixtures, 'posts.yml'))
    assert_equal [1, 2, 3], users.values.map { |attrs| attrs['id'] }
    assert_equal [1, 2, 3], posts.values.map { |attrs| attrs['id'] }
  end

  def test_explicit_id_collision_within_one_record_type
    File.write(File.join(@vials, 'users.vial.rb'), <<~'RUBY')
      vial :users do
        base do
          id 7
          name "first"
        end

        generate 1
      end

      vial :extra_users, record_type: :user do
        base do
          id 7
          name "second"
        end

        generate 1
      end
    RUBY

    error = assert_raises(Vial::ValidationError) { Vial.compile! }

    assert_equal 'ExplicitIDCollision', error.type
    assert_includes error.message, 'record_type: user'
  end

  def test_unused_sequence_warns
    File.write(File.join(@vials, 'users.vial.rb'), <<~'RUBY')
      vial :users do
        sequence(:email) { |i| "user#{i}@example.com" }

        base do
          name "user"
        end

        generate 1
      end
    RUBY

    _out, err = capture_io { Vial.compile! }

    assert_includes err, 'sequence :email in vial :users is defined but never referenced'
    assert_includes err, 'email sequence(:email)'
  end

  def test_referenced_sequence_does_not_warn
    File.write(File.join(@vials, 'users.vial.rb'), <<~'RUBY')
      vial :users do
        sequence(:email) { |i| "user#{i}@example.com" }

        variant :admin do
          email sequence(:email)
        end

        generate 1, :admin
      end
    RUBY

    _out, err = capture_io { Vial.compile! }

    refute_includes err, 'never referenced'
  end

  def test_abstract_vial_sequences_do_not_warn
    File.write(File.join(@vials, 'users.vial.rb'), <<~'RUBY')
      vial :base_users, abstract: true do
        sequence(:email) { |i| "user#{i}@example.com" }
      end

      vial :users do
        include_vial :base_users

        base do
          email sequence(:email)
        end

        generate 2
      end
    RUBY

    _out, err = capture_io { Vial.compile! }

    refute_includes err, 'never referenced'
    data = YAML.load_file(File.join(@fixtures, 'users.yml'))
    assert_equal %w[user1@example.com user2@example.com], data.values.map { |attrs| attrs['email'] }
  end
end
