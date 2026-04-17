# == Schema Information
#
# Table name: operators
#
#  id               :integer          not null, primary key
#  aircraft_count   :integer          default(0), not null
#  country          :string
#  country_id       :integer
#  created_at       :datetime         not null
#  field_provenance :jsonb            default("{}"), not null
#  iata_code        :string
#  icao_code        :string
#  last_combined_at :datetime
#  name             :string
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_operators_on_country_id  (country_id)
#

require "test_helper"

class OperatorTest < ActiveSupport::TestCase
  # ==========================================================================
  # Tests for parent-child relationships (task-003)
  # ==========================================================================

  test 'standalone? returns true for operator with no parent or children' do
    operator = Operator.new(name: 'Test Airline')
    # Mock the child_operators.exists? call
    operator.define_singleton_method(:child_operators) { Operator.none }

    assert operator.standalone?
  end

  test 'child? returns true for operator with parent_operator_id' do
    operator = Operator.new(name: 'Test Subsidiary', parent_operator_id: 1)

    assert operator.child?
    assert_not operator.standalone?
  end

  test 'child? returns false for operator without parent_operator_id' do
    operator = Operator.new(name: 'Test Airline', parent_operator_id: nil)

    assert_not operator.child?
  end

  test 'parent-child relationship works bidirectionally' do
    # Create parent operator
    parent = Operator.create!(name: 'Royal Air Force', country: nil)

    # Create child operators with different ICAO codes
    child1 = Operator.create!(name: 'Royal Air Force', icao_code: 'RRR', parent_operator: parent)
    child2 = Operator.create!(name: 'Royal Air Force', icao_code: 'RRF', parent_operator: parent)

    # Verify relationships
    assert_includes parent.child_operators, child1
    assert_includes parent.child_operators, child2
    assert_equal parent, child1.parent_operator
    assert_equal parent, child2.parent_operator

    # Verify helper methods
    assert parent.parent?
    assert_not parent.child?
    assert_not parent.standalone?

    assert child1.child?
    assert_not child1.parent?
    assert_not child1.standalone?
  end
end
