# == Schema Information
#
# Table name: aircraft_type_sources
#
#  id           :integer          not null, primary key
#  name         :string
#  type_code    :string
#  manufacturer :string
#  wtc          :string
#  category     :string
#  engines      :integer
#  engine_type  :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#

module Source
  module AircraftType
    class CfappsICAOIntAircraftTypeSource < Source::AircraftType::AircraftTypeSource
    end
  end
end
