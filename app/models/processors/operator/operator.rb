# frozen_string_literal: true

module Processors
  module Operator
    # Base class for operator-related processors
    class Operator < Processors::Base

      OPERATOR_REWRITE_PATTERNS = [
        [/Royal Flying Doctor Service.*/, 'Royal Flying Doctor Service'],
        [/State Of New South Wales Represented By Nsw Police Force/, 'NSW Police Force'],
        [/State Of New South Wales Represented By Nsw Rural Fire Service/, 'NSW Rural Fire Service'],
        [/State Of Western Australia - Represented By Commissioner Of Police/, 'Western Australia Police Force'],
      ].freeze

      @transform_data = {}

      class << self
        def combine_sources
          # Full outer join VRS to OTD
          vrs = Source::Operator::VRSDataOperatorSource.all

          otd_ids = Source::Operator::OpenTravelOperatorSource.all.pluck(:id)
          errors = []

          ::Operator.transaction do
            ActiveRecord::Base.logger.silence do
              vrs.each do |v_record|
                # Match on Name + one of ICAO or IATA code
                o_record = if v_record.icao_code.nil?
                            Source::Operator::OpenTravelOperatorSource.with_iata_and_name(v_record.iata_code, v_record.name).first
                           else
                            Source::Operator::OpenTravelOperatorSource.with_icao_and_name(v_record.icao_code, v_record.name).first
                           end

                # if there isn't a match,
                #   lookup just the ICAO or just the IATA, compare names for the matching records, choose the highest confidence.
                if o_record.nil?
                  Rails.logger.debug 'No Match found by name, doing fuzzy match..'
                  candidate_match = { id: nil, confidence: 0 }
                  confidence_threshold = v_record.icao_code.present? ? 0.5 : 0.75

                  possible_matches = Source::Operator::OpenTravelOperatorSource
                  if v_record.icao_code
                    possible_matches = possible_matches.merge(Source::Operator::OpenTravelOperatorSource.where(icao_code: v_record.icao_code))
                  end
                  if v_record.iata_code
                    possible_matches = possible_matches.merge(Source::Operator::OpenTravelOperatorSource.where(iata_code: v_record.iata_code))
                  end

                  possible_matches.each do |match|
                    Rails.logger.debug "Candidate: #{match.inspect}"
                    match_confidence = if (v_record.icao_code == match.icao_code) && (v_record.iata_code == match.iata_code)
                                       1.0
                                     else
                                       name_scores = []
                                       all_names = [match.name]
                                       all_names += match.data['alt_names'] if match.data['alt_names'].present?
                                       all_names.each do |name|
                                         name_scores.append(
                                           JaroWinkler.distance(v_record.name, name)
                                         )
                                       end
                                       name_scores.max
                                     end

                    Rails.logger.debug "Confidence: #{match_confidence}"
                    if match_confidence >= confidence_threshold && match_confidence > candidate_match[:confidence]
                      candidate_match = { id: match.id, confidence: match_confidence }
                    end
                  end

                  o_record = possible_matches.find { |match| candidate_match[:id] == match.id }

                  Rails.logger.debug "Best Match: #{o_record.inspect}"
                end

                # If we have a match between the two, prefer VRS attributes.
                if o_record&.present?
                  new_operator = ::Operator.new
                  new_operator.name = preferred_attr(:name, v_record, o_record)
                  new_operator.icao_code = preferred_attr(:icao_code, v_record, o_record)
                  new_operator.iata_code = preferred_attr(:iata_code, v_record, o_record)
                  if new_operator.valid?
                    new_operator.save
                  else
                    errors << {
                      record: new_operator,
                      source: 'Merged',
                      error: new_operator.errors
                    }
                  end

                  otd_ids.delete(o_record.id) # mark this record as used.
                else
                  # else, just create without OTD data.
                  obj = ::Operator.new(name: v_record.name, icao_code: v_record.icao_code, iata_code: v_record.iata_code)
                  if obj.valid?
                    obj.save
                  else
                    errors << {
                      record: v_record,
                      source: 'VRS',
                      error: new_operator.errors
                    }
                  end
                end
              end

              # complete the full outer join and add the un-matched OTD records.
              otd_ids.each do |o_id|
                record = Source::Operator::OpenTravelOperatorSource.find(o_id)
                begin
                  ::Operator.create!(name: record.name, icao_code: record.icao_code, iata_code: record.iata_code)
                rescue ActiveRecord::RecordInvalid => e
                  errors << {
                    record: record,
                    error: e
                  }
                  next
                end
              end
            end
          end

          errors.any? ? errors : true
        end

        def preferred_attr(attr, high_pref_record, low_pref_record)
          return high_pref_record&.send(attr) if high_pref_record.respond_to?(attr)

          low_pref_record&.send(attr)
        end

        def normalise_name(name)
          OPERATOR_REWRITE_PATTERNS.each { |p| name.gsub!(p[0], p[1]) }
          name
        end
      end
    end
  end
end
