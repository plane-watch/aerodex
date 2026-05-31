# frozen_string_literal: true

# == Schema Information
#
# Table name: routes
#
#  id                   :integer          not null, primary key
#  call_sign            :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  operator_id          :integer          not null
#  route_segments_count :integer          default("0"), not null
#
# Indexes
#
#  index_routes_on_operator_id                (operator_id)
#  index_routes_on_operator_id_and_call_sign  (operator_id,call_sign) UNIQUE
#

# Represents a flight route operated under a callsign, composed of an ordered
# sequence of RouteSegments (the airports called at, in order of flight).
class Route < ApplicationRecord
  include MeiliSearch::Rails
  extend Pagy::Meilisearch

  has_many :route_segments, dependent: :destroy
  belongs_to :operator

  # Allows the combine processor to stage a route together with its segments as
  # a single nested-attributes payload, applied atomically via the staged batch.
  accepts_nested_attributes_for :route_segments, allow_destroy: true

  # A route is uniquely identified by its operator and callsign.
  validates :call_sign, uniqueness: { scope: :operator_id }

  has_paper_trail
  # Preload associations for MeiliSearch reindexing to avoid N+1 queries
  scope :meilisearch_import, -> { includes(:operator) }

  meilisearch do
    attribute :id
    attribute :call_sign
    attribute :operator do
      operator&.name
    end

    filterable_attributes %i[id call_sign operator]
  end

  def string
    codes = []
    route_segments.each do |segment|
      codes.push(segment.airport.icao_code)
    end

    codes.join('-')
  end
end
