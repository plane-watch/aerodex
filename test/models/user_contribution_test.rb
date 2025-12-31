# == Schema Information
#
# Table name: user_contributions
#
#  id             :integer          not null, primary key
#  user_id        :integer          not null
#  entity_type    :string           not null
#  entity_id      :integer          not null
#  field_name     :string           not null
#  old_value      :jsonb
#  new_value      :jsonb
#  status         :string           default("pending"), not null
#  notes          :text
#  reviewed_by_id :integer
#  reviewed_at    :datetime
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  idx_user_contributions_entity               (entity_type,entity_id,field_name)
#  index_user_contributions_on_reviewed_by_id  (reviewed_by_id)
#  index_user_contributions_on_status          (status)
#  index_user_contributions_on_user_id         (user_id)
#

# frozen_string_literal: true

require 'test_helper'

class UserContributionTest < ActiveSupport::TestCase
  setup do
    @user = users(:new_contributor)
    @trusted_user = users(:trusted_contributor)
    @admin = users(:one)
    @operator = operators(:american_airlines)
  end

  # === Validations ===

  test 'valid with all required attributes' do
    contribution = UserContribution.new(
      user: @user,
      entity_type: 'Operator',
      entity_id: @operator.id,
      field_name: 'name',
      new_value: 'New Name'
    )

    assert contribution.valid?
  end

  test 'invalid without entity_type' do
    contribution = UserContribution.new(
      user: @user,
      entity_id: @operator.id,
      field_name: 'name',
      new_value: 'New Name'
    )

    assert_not contribution.valid?
    assert_includes contribution.errors[:entity_type], "can't be blank"
  end

  test 'invalid with unsupported entity_type' do
    contribution = UserContribution.new(
      user: @user,
      entity_type: 'InvalidModel',
      entity_id: 1,
      field_name: 'name',
      new_value: 'New Name'
    )

    assert_not contribution.valid?
    assert_includes contribution.errors[:entity_type], 'is not included in the list'
  end

  test 'invalid without new_value' do
    contribution = UserContribution.new(
      user: @user,
      entity_type: 'Operator',
      entity_id: @operator.id,
      field_name: 'name'
    )

    assert_not contribution.valid?
    assert_includes contribution.errors[:new_value], "can't be blank"
  end

  # === State Machine ===

  test 'initial state is pending' do
    contribution = UserContribution.new(
      user: @user,
      entity_type: 'Operator',
      entity_id: @operator.id,
      field_name: 'name',
      new_value: 'New Name'
    )

    assert contribution.pending?
  end

  test 'approve transitions from pending to approved' do
    contribution = create_contribution

    contribution.approve!(reviewer: @admin)

    assert contribution.approved?
  end

  test 'approve sets reviewed_by and reviewed_at' do
    contribution = create_contribution

    freeze_time do
      contribution.approve!(reviewer: @admin)

      assert_equal @admin, contribution.reviewed_by
      assert_equal Time.current, contribution.reviewed_at
    end
  end

  test 'approve applies the contribution to the entity' do
    contribution = create_contribution(new_value: 'Updated Airline Name')

    contribution.approve!(reviewer: @admin)

    @operator.reload
    assert_equal 'Updated Airline Name', @operator.name
  end

  test 'approve sets provenance on the entity' do
    contribution = create_contribution(new_value: 'Updated Airline Name')

    contribution.approve!(reviewer: @admin)

    @operator.reload
    assert @operator.has_provenance?(:name)
    assert_equal 'UserContribution', @operator.provenance_source_for(:name)
  end

  test 'approve increments contributor trust score' do
    initial_score = @user.contribution_trust_score
    contribution = create_contribution

    contribution.approve!(reviewer: @admin)

    @user.reload
    assert_equal initial_score + 1, @user.contribution_trust_score
  end

  test 'approve does not exceed trust score of 100' do
    @user.update!(contribution_trust_score: 100)
    contribution = create_contribution

    contribution.approve!(reviewer: @admin)

    @user.reload
    assert_equal 100, @user.contribution_trust_score
  end

  test 'reject transitions from pending to rejected' do
    contribution = create_contribution

    contribution.reject!(reviewer: @admin)

    assert contribution.rejected?
  end

  test 'reject sets reviewed_by and reviewed_at' do
    contribution = create_contribution

    freeze_time do
      contribution.reject!(reviewer: @admin)

      assert_equal @admin, contribution.reviewed_by
      assert_equal Time.current, contribution.reviewed_at
    end
  end

  test 'reject appends reason to notes' do
    contribution = create_contribution
    contribution.notes = 'Original note'

    contribution.reject!(reviewer: @admin, reason: 'Incorrect information')

    assert_includes contribution.notes, 'Original note'
    assert_includes contribution.notes, 'Rejection reason: Incorrect information'
  end

  test 'cannot approve an already approved contribution' do
    contribution = create_contribution
    contribution.approve!(reviewer: @admin)

    assert_raises AASM::InvalidTransition do
      contribution.approve!(reviewer: @admin)
    end
  end

  test 'cannot approve a rejected contribution' do
    contribution = create_contribution
    contribution.reject!(reviewer: @admin)

    assert_raises AASM::InvalidTransition do
      contribution.approve!(reviewer: @admin)
    end
  end

  # === Scopes ===

  test 'pending scope returns only pending contributions' do
    pending = create_contribution
    approved = create_contribution
    approved.approve!(reviewer: @admin)
    rejected = create_contribution
    rejected.reject!(reviewer: @admin)

    results = UserContribution.pending

    assert_includes results, pending
    assert_not_includes results, approved
    assert_not_includes results, rejected
  end

  test 'approved scope returns only approved contributions' do
    approved = create_contribution
    approved.approve!(reviewer: @admin)

    results = UserContribution.approved

    assert_includes results, approved
  end

  test 'rejected scope returns only rejected contributions' do
    rejected = create_contribution
    rejected.reject!(reviewer: @admin)

    results = UserContribution.rejected

    assert_includes results, rejected
  end

  test 'by_entity scope filters by entity type and id' do
    contribution_for_operator = create_contribution
    other_operator = operators(:united_airlines)
    contribution_for_other = create_contribution(entity_id: other_operator.id)

    results = UserContribution.by_entity('Operator', @operator.id)

    assert_includes results, contribution_for_operator
    assert_not_includes results, contribution_for_other
  end

  # === Helper Methods ===

  test 'entity returns the associated record' do
    contribution = create_contribution

    entity = contribution.entity

    assert_equal @operator, entity
  end

  test 'entity returns nil for non-existent record' do
    contribution = create_contribution(entity_id: 999_999)

    assert_nil contribution.entity
  end

  test 'from_trusted_user? returns true for trusted contributors' do
    contribution = UserContribution.new(
      user: @trusted_user,
      entity_type: 'Operator',
      entity_id: @operator.id,
      field_name: 'name',
      new_value: 'New Name'
    )

    assert contribution.from_trusted_user?
  end

  test 'from_trusted_user? returns false for non-trusted contributors' do
    contribution = UserContribution.new(
      user: @user,
      entity_type: 'Operator',
      entity_id: @operator.id,
      field_name: 'name',
      new_value: 'New Name'
    )

    assert_not contribution.from_trusted_user?
  end

  private

  def create_contribution(overrides = {})
    UserContribution.create!(
      {
        user: @user,
        entity_type: 'Operator',
        entity_id: @operator.id,
        field_name: 'name',
        old_value: @operator.name,
        new_value: 'Contributed Name'
      }.merge(overrides)
    )
  end
end
