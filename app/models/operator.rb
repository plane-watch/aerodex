# == Schema Information
#
# Table name: operators
#
#  id                 :integer          not null, primary key
#  name               :string
#  icao_code          :string
#  iata_code          :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  country_id         :integer
#  field_provenance   :jsonb            default("{}"), not null
#  last_combined_at   :datetime
#  aircraft_count     :integer          default("0"), not null
#  parent_operator_id :integer
#
# Indexes
#
#  index_operators_on_country_id          (country_id)
#  index_operators_on_parent_operator_id  (parent_operator_id)
#

## Notes:
## Consider normalising the call sign patterns into a separate table
class Operator < ApplicationRecord
  include MeiliSearch::Rails
  include HasFieldProvenance
  include BusinessNameNormalisation
  extend Pagy::Meilisearch

  has_many :aircraft
  has_many :aircraft_types, through: :aircraft

  has_many :routes
  has_many :route_segments, through: :routes

  belongs_to :country, optional: true, counter_cache: :operators_count

  # Parent-child relationships for multi-unit organisations (e.g., RAF, CAA).
  # Parent operators represent the organisation; children represent operational units
  # with distinct ICAO codes.
  belongs_to :parent_operator, class_name: 'Operator', optional: true
  has_many :child_operators, class_name: 'Operator', foreign_key: :parent_operator_id

  # Human-confirmed match decisions for this operator
  has_many :match_decisions, class_name: 'OperatorMatchDecision', dependent: :destroy

  validates :name, presence: true, allow_blank: false, uniqueness: { scope: %i[country_id icao_code], case_sensitive: false }
  validates :icao_code, allow_blank: true, format: { with: /\A[A-Z0-9]{3}\z/ }, uniqueness: { case_sensitive: false } # , scope: :active }
  validates :iata_code, allow_blank: true, format: { with: /\A[A-Z0-9]{2}\z/ }

  after_create :index!
  before_save :normalise_name_for_display

  has_paper_trail
  meilisearch do
    attribute :id
    attribute :name
    attribute :icao_code
    attribute :iata_code
    attribute :country do
      country&.name
    end

    filterable_attributes %i[id name icao_code iata_code country]
  end

  # Returns true if this operator has child operators (is an organisational parent).
  def parent?
    child_operators.exists?
  end

  # Returns true if this operator belongs to a parent organisation.
  def child?
    parent_operator_id.present?
  end

  # Returns true if this operator is standalone (neither parent nor child).
  def standalone?
    !parent? && !child?
  end

  private

  # Normalises the operator name by stripping corporate suffixes and titleizing.
  # E.g., "JETSTAR AIRWAYS PTY LTD" becomes "Jetstar Airways"
  def normalise_name_for_display
    self.name = normalise_business_name(name) if name.present?
  end
end
