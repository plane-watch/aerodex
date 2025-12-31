# == Schema Information
#
# Table name: source_trust_scores
#
#  id          :integer          not null, primary key
#  entity_type :string           not null
#  source_type :string           not null
#  field_name  :string
#  base_trust  :integer          default("50"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  idx_source_trust_scores_unique  (entity_type,source_type,field_name) UNIQUE
#

# frozen_string_literal: true

require 'test_helper'

class SourceTrustScoreTest < ActiveSupport::TestCase
  setup do
    SourceTrustScore.delete_all
  end

  test 'validates entity_type presence' do
    score = SourceTrustScore.new(source_type: 'VRSDataOperatorSource', base_trust: 80)
    assert_not score.valid?
    assert_includes score.errors[:entity_type], "can't be blank"
  end

  test 'validates entity_type inclusion' do
    score = SourceTrustScore.new(entity_type: 'InvalidType', source_type: 'TestSource', base_trust: 80)
    assert_not score.valid?
    assert_includes score.errors[:entity_type], 'is not included in the list'
  end

  test 'validates source_type presence' do
    score = SourceTrustScore.new(entity_type: 'Operator', base_trust: 80)
    assert_not score.valid?
    assert_includes score.errors[:source_type], "can't be blank"
  end

  test 'validates base_trust range' do
    score = SourceTrustScore.new(entity_type: 'Operator', source_type: 'TestSource', base_trust: 150)
    assert_not score.valid?
    assert_includes score.errors[:base_trust], 'must be less than or equal to 100'

    score.base_trust = -10
    assert_not score.valid?
    assert_includes score.errors[:base_trust], 'must be greater than or equal to 0'
  end

  test 'validates uniqueness of entity/source/field combination' do
    SourceTrustScore.create!(entity_type: 'Operator', source_type: 'VRSDataOperatorSource', base_trust: 80)

    duplicate = SourceTrustScore.new(entity_type: 'Operator', source_type: 'VRSDataOperatorSource', base_trust: 70)
    assert_not duplicate.valid?
  end

  test 'allows field-specific overrides' do
    SourceTrustScore.create!(entity_type: 'Operator', source_type: 'VRSDataOperatorSource', base_trust: 80)
    field_specific = SourceTrustScore.create!(
      entity_type: 'Operator',
      source_type: 'VRSDataOperatorSource',
      field_name: 'name',
      base_trust: 90
    )

    assert field_specific.valid?
    assert_equal 2, SourceTrustScore.where(source_type: 'VRSDataOperatorSource').count
  end

  test 'trust_for returns field-specific override when present' do
    SourceTrustScore.create!(entity_type: 'Operator', source_type: 'TestSource', base_trust: 70)
    SourceTrustScore.create!(entity_type: 'Operator', source_type: 'TestSource', field_name: 'name', base_trust: 90)

    assert_equal 90, SourceTrustScore.trust_for(entity_type: 'Operator', source_type: 'TestSource', field_name: 'name')
    assert_equal 70, SourceTrustScore.trust_for(entity_type: 'Operator', source_type: 'TestSource', field_name: 'icao_code')
  end

  test 'trust_for returns default when no override exists' do
    assert_equal SourceTrustScore::DEFAULT_TRUST,
                 SourceTrustScore.trust_for(entity_type: 'Operator', source_type: 'UnknownSource')
  end
end
