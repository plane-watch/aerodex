require 'test_helper'

class VRSDataOperatorProcessorTest < ActiveSupport::TestCase
  def setup
    @mock_data_hostname = 'testvrsdata.com'

    @sample_data = {
      complete_record: 'Code,Name,ICAO,IATA,PositioningFlightPattern,CharterFlightPattern
      VIR,Virgin Atlantic,VIR,VS,8\d\dP$,9\d\d\d',
      iata_only: 'Code,Name,ICAO,IATA,PositioningFlightPattern,CharterFlightPattern
      1B,Abacus International,,1B,,
      1C,Electronic Data Systems,,1C,,
      1D,Radixx Solutions International,,1D,,',
      non_unique_iata: 'Code,Name,ICAO,IATA,PositioningFlightPattern,CharterFlightPattern
      DYA,Dynamic Airlines,DYA,2D,,
      EAL,Eastern Airlines,EAL,2D,,',
      non_unique_iata_icao: 'Code,Name,ICAO,IATA,PositioningFlightPattern,CharterFlightPattern
      FBW,Aviation Data Systems,FBW,,,
      FBW,Aviation Data Network,FBW,,,'
    }

    # Setup Excon stubs
    @sample_data.each do |name, data|
      Excon.stub(
        {
          scheme: 'https', host: @mock_data_hostname,
          path: "/#{name}.csv", port: 443
        },
        { body: data, status: 200 }
      )
    end

    # Clear the Database
    VRSDataOperatorSource.delete_all
  end

  def url_for_test_name(test_name)
    "https://#{@mock_data_hostname}/#{test_name}.csv"
  end

  # Test importing a complete record with all fields populated
  ## We expect the 3 key fields to be present plus two in the JSONB data
  def test_complete_record
    VRSDataOperatorProcessor.import(url_for_test_name('complete_record'))

    where_complete = VRSDataOperatorSource.where(icao_code: 'VIR')

    assert_equal 1, where_complete.count
    assert_equal 'VIR', where_complete.first.icao_code
    assert_equal 'VS', where_complete.first.iata_code
    assert_equal 'Virgin Atlantic', where_complete.first.name
    assert_equal(
      HashWithIndifferentAccess.new({ icao_code: 'VIR', iata_code: 'VS', name: 'Virgin Atlantic',
                                      positioning_callsign_pattern: '8\d\dP$', charter_callsign_pattern: '9\d\d\d' }),
      where_complete.first.data
    )
  end

  # Test importing data with only an IATA code
  ## We expect the model to be valid and import all records.
  def test_vrs_iata_only_import
    VRSDataOperatorProcessor.import(url_for_test_name('iata_only'))

    where_record_1b = VRSDataOperatorSource.where(iata_code: '1B')

    assert_equal 3, VRSDataOperatorSource.count
    assert_equal 1, where_record_1b.count
    assert_equal 'Abacus International', where_record_1b.first.name
    assert_nil where_record_1b.first.icao_code
  end

  # Test importing data with a non-unique IATA code but with unique ICAO code
  ## Where there is a unique ICAO code, we expect both records to be imported.
  def test_vrs_non_unique_iata_import
    VRSDataOperatorProcessor.import(url_for_test_name('non_unique_iata'))

    where_record_2b = VRSDataOperatorSource.where(iata_code: '2D')
    assert_equal 2, where_record_2b.count
  end

  # Test importing data with duplicate entries
  ## Where there are duplicate entries, we expect the last to be imported (with an update)
  def test_vrs_non_unique_rows_import
    VRSDataOperatorProcessor.import(url_for_test_name('non_unique_iata_icao'))

    where_fbw = VRSDataOperatorSource.where(icao_code: 'FBW')

    assert_equal 1, where_fbw.count
  end
end
