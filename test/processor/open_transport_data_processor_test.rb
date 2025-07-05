require 'test_helper'

class OpenTransportOperatorProcessorTest < ActiveSupport::TestCase
  def setup
    @mock_data_hostname = 'otdata.com'

    @sample_data = {
      expired_record_only: 'pk^env_id^validity_from^validity_to^3char_code^2char_code^num_code^name^name2^alliance_code^alliance_status^type^wiki_link^flt_freq^alt_names^bases^key^version^parent_pk_list^successor_pk_list
      air-vista-georgia-v1^1^2014-08-04^2015-05-31^AJD^GT^0^flyvista^^^^^https://en.wikipedia.org/wiki/Flyvista^^en|flyvista|p=en|Vista Georgia|^TBS^air-vista-georgia^1^^',
      expired_record_and_valid: 'pk^env_id^validity_from^validity_to^3char_code^2char_code^num_code^name^name2^alliance_code^alliance_status^type^wiki_link^flt_freq^alt_names^bases^key^version^parent_pk_list^successor_pk_list
      air-abakan-avia-v1^1^1992-01-01^2014-07-10^ABG^4R^^Abakan-Avia^^^^^https://en.wikipedia.org/wiki/Abakan-Avia^^en|Royal Flight|p=en|Abakan-Avia|h=ru|Авиакомпания «Роял Флайт»|p=ru|Авиакомпания «Абакан-Авиа»|h^ABA^air-royal-flight^1^^
      air-abakan-avia-v2^^2014-07-11^^ABG^RL^^Royal Flight^^^^^https://en.wikipedia.org/wiki/Royal_Flight_%28airline%29^^en|Royal Flight|p=en|Abakan-Avia|h=ru|Авиакомпания «Роял Флайт»|p=ru|Авиакомпания «Абакан-Авиа»|h^VKO^air-royal-flight^2^^',
      duplicate_icao_different_name: 'pk^env_id^validity_from^validity_to^3char_code^2char_code^num_code^name^name2^alliance_code^alliance_status^type^wiki_link^flt_freq^alt_names^bases^key^version^parent_pk_list^successor_pk_list
      air-amelia-v1^^2020-02-01^^AIA^8R^942^Amelia^^^^^https://en.wikipedia.org/wiki/Sol_L%C3%ADneas_A%C3%A9reas^^en|Amelia|^^air-amelia^1^^
      air-avies-v1^^^^AIA^U3^0^Avies^^^^^^^en|Avies|^^air-avies^1^^',
      duplicate_iata_different_name: 'pk^env_id^validity_from^validity_to^3char_code^2char_code^num_code^name^name2^alliance_code^alliance_status^type^wiki_link^flt_freq^alt_names^bases^key^version^parent_pk_list^successor_pk_list
      air-netjets-aviation-v1^^^^EJA^1I^0^Netjets Aviation^^^^^^^en|Netjets Aviation|^^air-netjets-aviation^1^^
      air-netjets-europe-v1^^^^NJE^1I^0^Netjets Europe^^^^^^^en|Netjets Europe|^^air-netjets-europe^1^^',
      valid_unique_record: 'pk^env_id^validity_from^validity_to^3char_code^2char_code^num_code^name^name2^alliance_code^alliance_status^type^wiki_link^flt_freq^alt_names^bases^key^version^parent_pk_list^successor_pk_list
      air-qantas-v1^^1921-03-01^^QFA^QF^81^Qantas^^OneWorld^Member^^https://en.wikipedia.org/wiki/Qantas^265375^en|Qantas|^^air-qantas^1^^',
      record_becomes_invalid_before: 'pk^env_id^validity_from^validity_to^3char_code^2char_code^num_code^name^name2^alliance_code^alliance_status^type^wiki_link^flt_freq^alt_names^bases^key^version^parent_pk_list^successor_pk_list
      air-virgin-australia-v1^1^2000-08-31^^VOZ^DJ^856^Virgin Australia^^^^^https://en.wikipedia.org/wiki/Virgin_Australia^^en|Virgin Australia|=en|Virgin Blue|h=en|Pacific Blue|h=en|Virgin Australia Regional|h=en|SkyWest|h^^air-virgin-australia^1^m|air-virgin-australia-regional-v1^',
      record_becomes_invalid_after: 'pk^env_id^validity_from^validity_to^3char_code^2char_code^num_code^name^name2^alliance_code^alliance_status^type^wiki_link^flt_freq^alt_names^bases^key^version^parent_pk_list^successor_pk_list
      air-virgin-australia-v1^1^2000-08-31^2012-12-31^VOZ^DJ^856^Virgin Australia^^^^^https://en.wikipedia.org/wiki/Virgin_Australia^^en|Virgin Australia|=en|Virgin Blue|h=en|Pacific Blue|h=en|Virgin Australia Regional|h=en|SkyWest|h^^air-virgin-australia^1^m|air-virgin-australia-regional-v1^'
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
    Source::Operator::OpenTravelOperatorSource.delete_all
  end

  def url_for_test_name(test_name)
    "https://#{@mock_data_hostname}/#{test_name}.csv"
  end

  # Should skip expired records on first import
  def test_expired_record_only
    Processor::Operator::OpenTravel.import(url_for_test_name('expired_record_only'))

    where_non_exist = Source::Operator::OpenTravelOperatorSource.where(icao_code: 'AJD')

    assert_equal 0, where_non_exist.count
  end

  # The non-valid record should be skipped and the valid one of the same name should be imported
  def test_expired_record_and_valid
    Processor::Operator::OpenTravel.import(url_for_test_name('expired_record_and_valid'))

    where_abg = Source::Operator::OpenTravelOperatorSource.where(icao_code: 'ABG')

    assert_equal 1, where_abg.count
    assert_equal 'Royal Flight', where_abg.first.name
  end

  # Duplicate ICAO codes because both are indicating as valid.
  def test_duplicate_icao_different_names
    Processor::Operator::OpenTravel.import(url_for_test_name('duplicate_icao_different_name'))

    where_aia = Source::Operator::OpenTravelOperatorSource.where(icao_code: 'AIA')

    assert_equal 2, where_aia.count
  end

  def test_duplicate_icao_different_names_second_import
    Processor::Operator::OpenTravel.import(url_for_test_name('duplicate_icao_different_name'))

    where_aia = Source::Operator::OpenTravelOperatorSource.where(icao_code: 'AIA')
    where_8r = Source::Operator::OpenTravelOperatorSource.where(icao_code: 'AIA', iata_code: '8R')
    where_u3 = Source::Operator::OpenTravelOperatorSource.where(icao_code: 'AIA', iata_code: 'U3')

    assert_equal 2, where_aia.count
    assert_equal 'Amelia', where_8r.first.name
    assert_equal 'Avies', where_u3.first.name
  end

  def test_duplicate_iata_different_names
    Processor::Operator::OpenTravel.import(url_for_test_name('duplicate_iata_different_name'))

    where_1i = Source::Operator::OpenTravelOperatorSource.where(iata_code: '1I')

    assert_equal 2, where_1i.count
  end

  def test_duplicate_iata_different_names_second_import
    Processor::Operator::OpenTravel.import(url_for_test_name('duplicate_iata_different_name'))

    where_1i = Source::Operator::OpenTravelOperatorSource.where(iata_code: '1I')
    where_nje = Source::Operator::OpenTravelOperatorSource.where(iata_code: '1I', icao_code: 'NJE')
    where_eja = Source::Operator::OpenTravelOperatorSource.where(iata_code: '1I', icao_code: 'EJA')

    assert_equal 2, where_1i.count
    assert_equal 'Netjets Aviation', where_eja.first.name
    assert_equal 'Netjets Europe', where_nje.first.name
  end

  def test_valid_unique_record
    Processor::Operator::OpenTravel.import(url_for_test_name('valid_unique_record'))

    where_qfa = Source::Operator::OpenTravelOperatorSource.where(icao_code: 'QFA')

    assert_equal 1, where_qfa.count
  end

  def test_record_becomes_invalid
    travel_to Date.new(2010, 01, 01) do
      Processor::Operator::OpenTravel.import(url_for_test_name('record_becomes_invalid_before'))
    end

    where_before = Source::Operator::OpenTravelOperatorSource.where(icao_code: 'VOZ')
    assert_equal 1, where_before.count
    assert_equal 'VOZ', where_before.first.icao_code
    assert_equal 'DJ', where_before.first.iata_code
    assert_equal 'Virgin Australia', where_before.first.name
    assert_equal '2000-08-31', where_before.first.data['validity_from']

    travel_to Date.new(2013, 01, 01) do
      Processor::Operator::OpenTravel.import(url_for_test_name('record_becomes_invalid_after'))
    end

    where_after = Source::Operator::OpenTravelOperatorSource.where(icao_code: 'VOZ')
    assert_equal 1, where_after.count
    assert_equal 'VOZ', where_after.first.icao_code
    assert_equal 'DJ', where_after.first.iata_code
    assert_equal 'Virgin Australia', where_after.first.name
    assert_equal '2000-08-31', where_after.first.data['validity_from']
    assert_equal '2012-12-31', where_after.first.data['validity_to']
  end
end
