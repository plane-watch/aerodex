# == Schema Information
#
# Table name: operator_match_decisions
#
#  id                :integer          not null, primary key
#  operator_id       :integer          not null
#  matched_name      :string           not null
#  matched_icao_code :string
#  decision_type     :integer          default("0"), not null
#  decided_by        :string
#  notes             :text
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  idx_match_decisions_unique_name_icao                 (matched_name,matched_icao_code) UNIQUE
#  index_operator_match_decisions_on_matched_icao_code  (matched_icao_code)
#  index_operator_match_decisions_on_matched_name       (matched_name)
#  index_operator_match_decisions_on_operator_id        (operator_id)
#

# Stores human-confirmed operator matching decisions.
#
# When an operator name from a source cannot be automatically matched to an Operator record,
# a human can review and create a decision record. Future imports will use these decisions
# to match the same name/ICAO to the confirmed Operator.
#
# == Decision Types
# - confirmed_match: The source name/ICAO correctly matches this Operator
# - rejected_match: The source name/ICAO should NOT match this Operator
# - new_operator: A new Operator record should be created for this name/ICAO
#
class OperatorMatchDecision < ApplicationRecord
  belongs_to :operator

  # Decision types for matching operators
  enum :decision_type, {
    confirmed_match: 0, # Human confirmed this name/ICAO maps to this Operator
    rejected_match: 1,  # Human rejected this as an incorrect match
    new_operator: 2     # Human decided this should be a new Operator
  }, prefix: true

  validates :matched_name, presence: true
  validates :decision_type, presence: true
  validates :matched_name, uniqueness: { scope: :matched_icao_code }

  # Finds the confirmed operator for a given name and optional ICAO code.
  #
  # @param name [String] The operator name from the source
  # @param icao_code [String, nil] The operator ICAO code from the source
  # @return [Operator, nil] The confirmed operator, or nil if no decision exists
  def self.find_confirmed_operator(name, icao_code: nil)
    decision = decision_type_confirmed_match
               .where(matched_name: name.downcase)
               .where(matched_icao_code: icao_code)
               .first

    decision&.operator
  end

  # Records a human decision for an operator match.
  #
  # @param operator [Operator] The operator to match to
  # @param name [String] The operator name from the source
  # @param icao_code [String, nil] The operator ICAO code from the source
  # @param decision [Symbol] One of :confirmed_match, :rejected_match, :new_operator
  # @param decided_by [String, nil] Who made the decision (username, etc.)
  # @param notes [String, nil] Optional notes about the decision
  # @return [OperatorMatchDecision] The created or updated decision record
  def self.record_decision(operator:, name:, icao_code: nil, decision:, decided_by: nil, notes: nil)
    find_or_initialize_by(
      matched_name: name.downcase,
      matched_icao_code: icao_code
    ).tap do |record|
      record.operator = operator
      record.decision_type = decision
      record.decided_by = decided_by
      record.notes = notes
      record.save!
    end
  end
end
