# frozen_string_literal: true

require 'test_helper'

module Processors
  module Route
    class VrsTest < ActiveSupport::TestCase
      CSV_DATA = <<~CSV
        Callsign,Code,Number,AirlineCode,AirportCodes
        QFA1,QFA,1,QFA,YSSY-WSSS-EGLL
        QFA10,QFA,10,QFA,EGLL-YPPH
      CSV

      setup do
        Source::Route::VRSRouteSource.delete_all
      end

      test 'import_csv_data upserts rows into the source table' do
        Processors::Route::VRS.import_csv_data(CSV_DATA, source_name: 'QFA-all.csv')

        assert_equal 2, Source::Route::VRSRouteSource.count

        qfa1 = Source::Route::VRSRouteSource.find_by(callsign: 'QFA1')
        assert_equal 'QFA', qfa1.airline_code
        assert_equal 'YSSY-WSSS-EGLL', qfa1.airport_codes
        assert_equal '1', qfa1.data['Number']
        assert_equal 'QFA', qfa1.data['Code']
      end

      test 'import_csv_data strips a UTF-8 BOM from the header' do
        bom = "\xEF\xBB\xBF".dup.force_encoding('UTF-8')
        Processors::Route::VRS.import_csv_data(bom + CSV_DATA, source_name: 'bom.csv')

        assert_equal 2, Source::Route::VRSRouteSource.count
        assert Source::Route::VRSRouteSource.exists?(callsign: 'QFA1')
      end

      test 'import_csv_data is idempotent on re-import' do
        2.times { Processors::Route::VRS.import_csv_data(CSV_DATA, source_name: 'QFA-all.csv') }
        assert_equal 2, Source::Route::VRSRouteSource.count
      end

      test 'import_csv_data skips rows missing required fields' do
        bad = "Callsign,Code,Number,AirlineCode,AirportCodes\n,,,,\n"
        result = Processors::Route::VRS.import_csv_data(bad, source_name: 'bad.csv')

        assert_equal 0, Source::Route::VRSRouteSource.count
        assert_equal 1, result[:error_count]
      end

      test 'import_airline fetches the -all.csv file via Excon' do
        Excon.stub(
          { scheme: 'https', host: 'raw.githubusercontent.com',
            path: '/vradarserver/standing-data/main/routes/schema-01/Q/QFA-all.csv', port: 443 },
          { body: CSV_DATA, status: 200 }
        )

        Processors::Route::VRS.import_airline('QFA')

        assert_equal 2, Source::Route::VRSRouteSource.count
      ensure
        Excon.stubs.clear
      end
    end
  end
end
