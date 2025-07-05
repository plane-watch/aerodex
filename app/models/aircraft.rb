# == Schema Information
#
# Table name: aircraft
#
#  id                      :bigint           not null, primary key
#  aircraft_name           :string
#  cabin_configuration     :string
#  engine_count            :integer
#  engine_model            :string
#  icao                    :string
#  manufacture_year        :integer
#  model                   :string
#  owner                   :string
#  registration            :string
#  registration_date       :date
#  serial_number           :string
#  status                  :integer          default("active")
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  aircraft_type_id        :integer
#  operator_id             :integer
#  registration_country_id :bigint           not null
#
# Indexes
#
#  index_aircraft_on_aircraft_type_id         (aircraft_type_id)
#  index_aircraft_on_operator_id              (operator_id)
#  index_aircraft_on_registration_country_id  (registration_country_id)
#
# Foreign Keys
#
#  fk_rails_...  (registration_country_id => countries.id)
#
class Aircraft < ApplicationRecord
  include MeiliSearch::Rails
  extend Pagy::Meilisearch

  ActiveRecord::Relation.include Pagy::Meilisearch

  belongs_to :aircraft_type
  belongs_to :operator
  belongs_to :registration_country, class_name: 'Country'

  has_one :manufacturer, through: :aircraft_type
  enum :status, { active: 0, withdrawn: 1, hull_loss: 2, scrapped: 3, stored: 4, written_off: 5 }

  delegate :name, to: :aircraft_type

  validates :icao, presence: true,
                   format: { with: /\A[\da-fA-F]{6}\z/, message: 'Not a valid 24-bit ModeS transponder code' }
  validates :registration, presence: true, aircraft_registration: true
  validates :serial_number, presence: true, allow_blank: false
  validates :owner, presence: true, allow_blank: false
  validates :operator, presence: true, allow_blank: false
  validates :registration_date, presence: true, allow_blank: false

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
      aircraft_type.name
    end
    attribute :aircraft_type_code do
      aircraft_type.type_code
    end
    attribute :aircraft_manufacturer do
      aircraft_type.manufacturer.name
    end
    attribute :operator do
      operator.name
    end

    displayed_attributes [:id]
  end
end
