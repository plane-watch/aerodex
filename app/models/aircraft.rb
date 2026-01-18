# == Schema Information
#
# Table name: aircraft
#
#  id                      :integer          not null, primary key
#  icao                    :string
#  aircraft_type_id        :integer
#  serial_number           :string
#  manufacture_year        :integer
#  owner                   :string
#  operator_id             :integer
#  registration            :string
#  registration_date       :date
#  engine_count            :integer
#  engine_model            :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  cabin_configuration     :string
#  aircraft_name           :string
#  status                  :integer          default("0")
#  model                   :string
#  registration_country_id :integer          not null
#  field_provenance        :jsonb            default("{}"), not null
#  last_combined_at        :datetime
#
# Indexes
#
#  index_aircraft_on_aircraft_type_id         (aircraft_type_id)
#  index_aircraft_on_operator_id              (operator_id)
#  index_aircraft_on_registration_country_id  (registration_country_id)
#

class Aircraft < ApplicationRecord
  include MeiliSearch::Rails
  include HasFieldProvenance
  extend Pagy::Meilisearch

  ActiveRecord::Relation.include Pagy::Meilisearch

  belongs_to :aircraft_type, counter_cache: true
  belongs_to :operator, counter_cache: true, optional: true
  belongs_to :registration_country, class_name: 'Country'

  has_one :manufacturer, through: :aircraft_type
  enum :status, { active: 0, withdrawn: 1, hull_loss: 2, scrapped: 3, stored: 4, written_off: 5 }

  delegate :name, to: :aircraft_type

  validates :icao, presence: true,
                   format: { with: /\A[\da-fA-F]{6}\z/, message: 'Not a valid 24-bit ModeS transponder code' }
  validates :registration, presence: true, aircraft_registration: true
  validates :serial_number, presence: true, allow_blank: false
  validates :owner, presence: true, allow_blank: false
  validates :registration_date, presence: true, allow_blank: true

  scope :meilisearch_import, -> { includes(:operator, aircraft_type: [:manufacturer]) }
  scope :search_for, lambda { |query|
                       if query.present?
                         where(id: search(query).raw_answer&.dig('hits')&.collect do |hit|
                                     hit['id']
                                   end)
                       end
                     }

  has_paper_trail

  meilisearch do
    attribute :icao
    attribute :registration
    attribute :serial_number
    attribute :owner
    attribute :aircraft_name
    attribute :model
    attribute :aircraft_type do
      aircraft_type&.name
    end
    attribute :aircraft_type_code do
      aircraft_type&.type_code
    end
    attribute :aircraft_manufacturer do
      aircraft_type&.manufacturer&.name
    end
    attribute :operator do
      operator&.name
    end
    attribute :operator_icao_code do
      operator&.icao_code
    end
    attribute :operator_iata_code do
      operator&.iata_code
    end

    # Enable field-specific filtering for advanced search.
    # These attributes can be used with the field:value search syntax.
    filterable_attributes %i[
      icao
      registration
      serial_number
      owner
      aircraft_name
      model
      aircraft_type
      aircraft_type_code
      aircraft_manufacturer
      operator
      operator_icao_code
      operator_iata_code
    ]
  end
end
