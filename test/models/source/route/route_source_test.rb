# == Schema Information
#
# Table name: route_sources
#
#  id               :integer          not null, primary key
#  type             :string           not null
#  callsign         :string           not null
#  airline_code     :string           not null
#  airport_codes    :string           not null
#  data             :jsonb            default("{}"), not null
#  import_date      :datetime         not null
#  excluded         :boolean          default(FALSE), not null
#  exclusion_reason :string
#  excluded_at      :datetime
#  excluded_by      :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_route_sources_on_airline_code       (airline_code)
#  index_route_sources_on_callsign_and_type  (callsign,type) UNIQUE
#  index_route_sources_on_data               (data)
#  index_route_sources_on_excluded           (excluded)
#

# frozen_string_literal: true

require 'test_helper'

module Source
  module Route
    class RouteSourceTest < ActiveSupport::TestCase
      def build_source(attrs = {})
        Source::Route::VRSRouteSource.new(
          {
            callsign: 'QFA1',
            airline_code: 'QFA',
            airport_codes: 'YSSY-WSSS-EGLL',
            import_date: Time.current
          }.merge(attrs)
        )
      end

      test 'is valid with the required fields' do
        assert build_source.valid?
      end

      test 'requires callsign, airline_code, airport_codes and import_date' do
        source = build_source(callsign: nil, airline_code: nil, airport_codes: nil, import_date: nil)
        assert_not source.valid?
        assert_includes source.errors.attribute_names, :callsign
        assert_includes source.errors.attribute_names, :airline_code
        assert_includes source.errors.attribute_names, :airport_codes
        assert_includes source.errors.attribute_names, :import_date
      end

      test 'airport_code_list splits the hyphenated airport codes in order' do
        assert_equal %w[YSSY WSSS EGLL], build_source.airport_code_list
      end

      test 'airport_code_list returns an empty array when airport_codes is nil' do
        assert_equal [], build_source(airport_codes: nil).airport_code_list
      end

      test 'airport_code_list returns a single-element array for a one-airport route' do
        assert_equal %w[YSSY], build_source(airport_codes: 'YSSY').airport_code_list
      end

      test 'includable scope excludes flagged records' do
        included = build_source(callsign: 'QFA10')
        included.save!
        excluded = build_source(callsign: 'QFA20')
        excluded.save!
        excluded.exclude!(reason: 'test')

        callsigns = Source::Route::VRSRouteSource.includable.pluck(:callsign)
        assert_includes callsigns, 'QFA10'
        assert_not_includes callsigns, 'QFA20'
      end
    end
  end
end
