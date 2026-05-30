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

      test 'import_airline falls back to split files when -all.csv is absent' do
        base_path = '/vradarserver/standing-data/main/routes/schema-01/Q'
        # The -all.csv file is absent (non-200 => get_source_from_url returns nil).
        Excon.stub(
          { scheme: 'https', host: 'raw.githubusercontent.com', path: "#{base_path}/QFA-all.csv", port: 443 },
          { status: 404 }
        )
        # Two split files carry data; the remaining digits are absent.
        Excon.stub(
          { scheme: 'https', host: 'raw.githubusercontent.com', path: "#{base_path}/QFA-0.csv", port: 443 },
          { body: "Callsign,Code,Number,AirlineCode,AirportCodes\nQFA1,QFA,1,QFA,YSSY-WSSS\n", status: 200 }
        )
        Excon.stub(
          { scheme: 'https', host: 'raw.githubusercontent.com', path: "#{base_path}/QFA-1.csv", port: 443 },
          { body: "Callsign,Code,Number,AirlineCode,AirportCodes\nQFA10,QFA,10,QFA,WSSS-YSSY\n", status: 200 }
        )
        (2..9).each do |digit|
          Excon.stub(
            { scheme: 'https', host: 'raw.githubusercontent.com', path: "#{base_path}/QFA-#{digit}.csv", port: 443 },
            { status: 404 }
          )
        end

        Processors::Route::VRS.import_airline('QFA')

        assert_equal 2, Source::Route::VRSRouteSource.count
        assert Source::Route::VRSRouteSource.exists?(callsign: 'QFA1')
        assert Source::Route::VRSRouteSource.exists?(callsign: 'QFA10')
      ensure
        Excon.stubs.clear
      end

      test 'fetch_available_paths returns only route CSV paths, sorted' do
        tree = {
          tree: [
            { path: 'routes/schema-01/Q/QFA-all.csv' },
            { path: 'routes/schema-01/Q/QFA-0.csv' },
            { path: 'routes/schema-01/README.md' },
            { path: 'airlines/schema-01/airlines.csv' }
          ]
        }.to_json
        Excon.stub(
          { scheme: 'https', host: 'api.github.com',
            path: '/repos/vradarserver/standing-data/git/trees/main',
            query: 'recursive=1', port: 443 },
          { body: tree, status: 200 }
        )

        paths = Processors::Route::VRS.fetch_available_paths

        assert_equal ['routes/schema-01/Q/QFA-0.csv', 'routes/schema-01/Q/QFA-all.csv'], paths
      ensure
        Excon.stubs.clear
      end

      test 'import_csv_data rescues malformed CSV and reports one error' do
        malformed = %Q(Callsign,Code,Number,AirlineCode,AirportCodes\nQFA1,QFA,1,QFA,"unterminated\n)
        result = Processors::Route::VRS.import_csv_data(malformed, source_name: 'broken.csv')

        assert_equal 0, Source::Route::VRSRouteSource.count
        assert_equal 1, result[:error_count]
      ensure
        Excon.stubs.clear
      end

      test 'flush de-duplicates repeated callsigns within a batch (last wins)' do
        data = "Callsign,Code,Number,AirlineCode,AirportCodes\nQFA1,QFA,1,QFA,YSSY-WSSS\nQFA1,QFA,1,QFA,EGLL-YPPH\n"
        Processors::Route::VRS.import_csv_data(data, source_name: 'dupes.csv')

        assert_equal 1, Source::Route::VRSRouteSource.count
        assert_equal 'EGLL-YPPH', Source::Route::VRSRouteSource.find_by(callsign: 'QFA1').airport_codes
      end
    end
  end
end
