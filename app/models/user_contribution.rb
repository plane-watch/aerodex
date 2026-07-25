# frozen_string_literal: true

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

# Tracks user-submitted data corrections and additions.
#
# UserContributions go through a review workflow managed by AASM:
# - pending: Awaiting review by an administrator
# - approved: The contribution has been accepted and applied
# - rejected: The contribution was not accepted
#
# Trusted users (contribution_trust_score >= 90) may have their contributions
# auto-approved in the future.
#
# @example Submitting a contribution
#   contribution = UserContribution.create!(
#     user: current_user,
#     entity_type: 'Operator',
#     entity_id: operator.id,
#     field_name: 'name',
#     old_value: operator.name,
#     new_value: 'Corrected Name',
#     notes: 'The official name uses different capitalisation'
#   )
#
# @example Approving a contribution
#   contribution.approve!(reviewed_by: admin_user)
class UserContribution < ApplicationRecord
  include AASM

  # The canonical entity types that can receive contributions
  VALID_ENTITY_TYPES = %w[
    Operator
    Aircraft
    AircraftType
    Manufacturer
    Country
    Airport
  ].freeze

  # The minimum trust score required for auto-approval
  AUTO_APPROVE_TRUST_THRESHOLD = 90

  belongs_to :user
  belongs_to :reviewed_by, class_name: 'User', optional: true

  validates :entity_type, presence: true, inclusion: { in: VALID_ENTITY_TYPES }
  validates :entity_id, presence: true
  validates :field_name, presence: true
  validates :new_value, presence: true

  # Scopes for the review queue
  scope :pending, -> { where(status: 'pending') }
  scope :approved, -> { where(status: 'approved') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :by_entity, ->(type, id) { where(entity_type: type, entity_id: id) }
  scope :recent, -> { order(created_at: :desc) }

  # AASM state machine for the contribution workflow
  aasm column: :status do
    state :pending, initial: true
    state :approved
    state :rejected

    event :approve do
      before do |reviewer: nil|
        self.reviewed_by = reviewer
        self.reviewed_at = Time.current
      end

      after do
        apply_contribution!
        update_contributor_trust!
      end

      transitions from: :pending, to: :approved
    end

    event :reject do
      before do |reviewer: nil, reason: nil|
        self.reviewed_by = reviewer
        self.reviewed_at = Time.current
        self.notes = [notes, "Rejection reason: #{reason}"].compact.join("\n") if reason.present?
      end

      transitions from: :pending, to: :rejected
    end
  end

  # Returns the entity record this contribution applies to.
  #
  # @return [ApplicationRecord, nil] The entity or nil if not found
  def entity
    entity_type.constantize.find_by(id: entity_id)
  end

  # Checks if the contributing user is trusted enough for auto-approval.
  #
  # @return [Boolean]
  def from_trusted_user?
    user.trusted_contributor?
  end

  private

  # Applies the contribution to the entity record.
  # Called after the contribution is approved.
  def apply_contribution!
    record = entity
    return unless record

    record.update!(field_name => new_value)

    # Update provenance if the model supports it
    return unless record.respond_to?(:set_provenance)

    record.set_provenance(
      field_name,
      source: self,
      confidence: calculate_contribution_confidence
    )
    record.save!
  end

  # Calculates the confidence score for this contribution.
  # Based on the contributor's trust score.
  #
  # @return [Integer] The confidence score (0-100)
  def calculate_contribution_confidence
    # User contributions start at their trust score, capped at 95
    # (only automated sources can reach 100)
    [user.contribution_trust_score, 95].min
  end

  # Increases the contributor's trust score slightly after approval.
  # Successful contributions build trust over time.
  def update_contributor_trust!
    return if user.contribution_trust_score >= 100

    # Small increment for each approved contribution
    new_score = [user.contribution_trust_score + 1, 100].min
    user.update!(contribution_trust_score: new_score)
  end
end
