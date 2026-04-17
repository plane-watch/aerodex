# == Schema Information
#
# Table name: countries
#
#  id               :integer          not null, primary key
#  iso_2char_code   :string
#  iso_3char_code   :string
#  iso_num_code     :string
#  name             :string
#  capital          :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  field_provenance :jsonb            default("{}"), not null
#  last_combined_at :datetime
#  airports_count   :integer          default("0"), not null
#  operators_count  :integer          default("0"), not null
#

class Country < ApplicationRecord
  include MeiliSearch::Rails
  include HasFieldProvenance
  extend Pagy::Meilisearch

  has_many :airports
  has_many :manufacturers
  has_many :operators
  has_many :flight_information_regions
  has_many :aircraft, foreign_key: :registration_country_id

  has_paper_trail

  meilisearch do
    attribute :id
    attribute :name
    attribute :iso_2char_code
    attribute :iso_3char_code
    attribute :capital

    filterable_attributes %i[id name iso_2char_code iso_3char_code capital]
  end

  # use the ISO3116 'countries' gem to ensure all countries have been created in our database.
  # Use the ISO 3-character code as the unique identifier.
  def self.sync_from_iso3166!
    ISO3166::Country.all.each do |country|
      Country.find_or_create_by!(iso_3char_code: country.alpha3) do |c|
        c.name = country.name
        c.iso_2char_code = country.alpha2
        c.iso_num_code = country.numeric
      end
    end
    reindex!
  end
end
