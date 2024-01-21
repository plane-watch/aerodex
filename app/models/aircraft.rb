# == Schema Information
#
# Table name: aircraft
#
#  id                    :bigint           not null, primary key
#  aircraft_name         :string
#  engine_count          :integer
#  engine_model          :string
#  icao                  :string
#  manufacture_year      :integer
#  model                 :string
#  owner                 :string
#  registration          :string
#  registration_country  :string
#  registration_date     :date
#  cabin_configuration :string
#  serial_number         :string
#  status                :integer          default("active")
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  aircraft_type_id      :integer
#  operator_id           :integer
#
class Aircraft < ApplicationRecord
  belongs_to :aircraft_type
  belongs_to :operator
  has_one :manufacturer, through: :aircraft_type
  enum status: { active: 0, withdrawn: 1, hull_loss: 2, scrapped: 3, stored: 4, written_off: 5 }

  delegate :name, to: :aircraft_type

  validates :icao, presence: true, format: { with: /\A[\da-fA-F]{6}\z/, message: "Not a valid 24-bit ModeS transponder code" }
  validates :registration, presence: true, aircraft_registration: true
  validates :serial_number, presence: true, allow_blank: false
  validates :owner, presence: true, allow_blank: false
  validates :operator, presence: true, allow_blank: false
  validates :registration_date, presence: true, allow_blank: false

  has_paper_trail
end
