# frozen_string_literal: true

require 'csv'
require 'net/http'
require 'uri'

# Service for looking up country codes from aircraft registration prefixes.
#
# Uses VRS (Virtual Radar Server) registration prefix data to map registrations
# like "VH-ABC" to their country ISO codes (e.g., "AU" for Australia).
#
# The data is loaded once from GitHub and cached in memory for fast lookups.
#
# @example
#   RegistrationPrefixLookup.country_code_for('VH-ABC')  # => 'AU'
#   RegistrationPrefixLookup.country_code_for('G-ABCD')  # => 'GB'
#   RegistrationPrefixLookup.country_code_for('N12345')  # => 'US'
#
# @see https://github.com/vradarserver/standing-data/tree/main/registration-prefixes/schema-01
class RegistrationPrefixLookup
  GITHUB_RAW_URL = 'https://raw.githubusercontent.com/vradarserver/standing-data/main/registration-prefixes/schema-01/reg-prefixes.csv'

  class << self
    # Looks up the ISO 2-character country code for an aircraft registration.
    #
    # @param registration [String] The aircraft registration (e.g., 'VH-ABC', 'N12345')
    # @return [String, nil] The ISO 2-character country code, or nil if not found
    def country_code_for(registration)
      return nil if registration.blank?

      ensure_data_loaded
      reg_upper = registration.upcase.gsub(/[^A-Z0-9]/, '') # Normalise: remove hyphens, uppercase

      # Try to match against each prefix, longest first
      @prefixes_by_length.each do |prefix_data|
        prefix = prefix_data[:prefix_normalised]
        next unless reg_upper.start_with?(prefix)

        # Verify with regex if available
        if prefix_data[:regex]
          return prefix_data[:country] if registration.upcase.match?(prefix_data[:regex])
        else
          return prefix_data[:country]
        end
      end

      nil
    end

    # Reloads the prefix data from GitHub.
    # Useful for refreshing after updates to the VRS repository.
    #
    # @return [Boolean] true if reload succeeded
    def reload!
      @prefixes_by_length = nil
      @loaded = false
      ensure_data_loaded
      @loaded
    end

    # Returns statistics about the loaded prefix data.
    #
    # @return [Hash] Stats including prefix count and sample mappings
    def stats
      ensure_data_loaded
      {
        prefix_count: @prefixes_by_length&.count || 0,
        sample_mappings: @prefixes_by_length&.first(10)&.map { |p| "#{p[:prefix]} => #{p[:country]}" }
      }
    end

    private

    def ensure_data_loaded
      return if @loaded

      load_from_github || load_fallback
      @loaded = true
    end

    def load_from_github
      uri = URI.parse(GITHUB_RAW_URL)
      response = Net::HTTP.get_response(uri)

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn "RegistrationPrefixLookup: Failed to fetch from GitHub: #{response.code}"
        return false
      end

      parse_csv(response.body)
      Rails.logger.info "RegistrationPrefixLookup: Loaded #{@prefixes_by_length.count} prefixes from GitHub"
      true
    rescue StandardError => e
      Rails.logger.error "RegistrationPrefixLookup: Error loading from GitHub: #{e.message}"
      false
    end

    def load_fallback
      # Fallback to common prefixes if GitHub is unavailable
      @prefixes_by_length = [
        { prefix: 'VH', prefix_normalised: 'VH', country: 'AU', regex: /\AVH-[A-Z]{3}\z/i },
        { prefix: 'ZK', prefix_normalised: 'ZK', country: 'NZ', regex: /\AZK-[A-Z]{3}\z/i },
        { prefix: 'ZS', prefix_normalised: 'ZS', country: 'ZA', regex: /\AZS-[A-Z]{3}\z/i },
        { prefix: 'G', prefix_normalised: 'G', country: 'GB', regex: /\AG-[A-Z]{4}\z/i },
        { prefix: 'N', prefix_normalised: 'N', country: 'US', regex: /\AN\d{1,5}[A-Z]{0,2}\z/i },
        { prefix: 'C', prefix_normalised: 'C', country: 'CA', regex: /\AC-[A-Z]{4}\z/i },
        { prefix: 'F', prefix_normalised: 'F', country: 'FR', regex: /\AF-[A-Z]{4}\z/i },
        { prefix: 'D', prefix_normalised: 'D', country: 'DE', regex: /\AD-[A-Z]{4}\z/i },
        { prefix: 'HB', prefix_normalised: 'HB', country: 'CH', regex: /\AHB-[A-Z]{3}\z/i },
        { prefix: 'I', prefix_normalised: 'I', country: 'IT', regex: /\AI-[A-Z]{4}\z/i },
        { prefix: 'PH', prefix_normalised: 'PH', country: 'NL', regex: /\APH-[A-Z]{3}\z/i },
        { prefix: 'EC', prefix_normalised: 'EC', country: 'ES', regex: /\AEC-[A-Z]{3}\z/i },
        { prefix: 'EI', prefix_normalised: 'EI', country: 'IE', regex: /\AEI-[A-Z]{3}\z/i },
        { prefix: 'OE', prefix_normalised: 'OE', country: 'AT', regex: /\AOE-[A-Z]{3}\z/i },
        { prefix: 'SE', prefix_normalised: 'SE', country: 'SE', regex: /\ASE-[A-Z]{3}\z/i },
        { prefix: 'LN', prefix_normalised: 'LN', country: 'NO', regex: /\ALN-[A-Z]{3}\z/i },
        { prefix: 'OH', prefix_normalised: 'OH', country: 'FI', regex: /\AOH-[A-Z]{3}\z/i },
        { prefix: 'OY', prefix_normalised: 'OY', country: 'DK', regex: /\AOY-[A-Z]{3}\z/i },
        { prefix: 'JA', prefix_normalised: 'JA', country: 'JP', regex: /\AJA\d{4}\z/i },
        { prefix: 'B', prefix_normalised: 'B', country: 'CN', regex: /\AB-\d{4}\z/i },
        { prefix: 'HL', prefix_normalised: 'HL', country: 'KR', regex: /\AHL\d{4}\z/i },
        { prefix: '9V', prefix_normalised: '9V', country: 'SG', regex: /\A9V-[A-Z]{3}\z/i },
        { prefix: 'VT', prefix_normalised: 'VT', country: 'IN', regex: /\AVT-[A-Z]{3}\z/i },
        { prefix: 'A6', prefix_normalised: 'A6', country: 'AE', regex: /\AA6-[A-Z]{3}\z/i },
        { prefix: 'A7', prefix_normalised: 'A7', country: 'QA', regex: /\AA7-[A-Z]{3}\z/i },
      ].sort_by { |p| -p[:prefix].length }

      Rails.logger.warn 'RegistrationPrefixLookup: Using fallback prefix data'
    end

    def parse_csv(csv_data)
      # Handle UTF-8 BOM
      csv_data = csv_data.dup.force_encoding('UTF-8')
      csv_data = csv_data.sub(/\A\xEF\xBB\xBF/u, '')

      prefixes = []

      CSV.parse(csv_data, headers: true) do |row|
        prefix = row['Prefix']&.strip
        country = row['CountryISO2']&.strip
        decode_regex = row['DecodeFullRegex']&.strip

        next if prefix.blank? || country.blank?

        # Build regex from the decode pattern
        regex = nil
        if decode_regex.present?
          begin
            regex = Regexp.new("\\A#{decode_regex}\\z", Regexp::IGNORECASE)
          rescue RegexpError
            # Skip invalid regex
          end
        end

        prefixes << {
          prefix: prefix,
          prefix_normalised: prefix.gsub(/[^A-Z0-9]/i, '').upcase,
          country: country,
          regex: regex
        }
      end

      # Sort by prefix length descending so longer prefixes match first
      # (e.g., "3DC" before "3D", "VH" before "V")
      @prefixes_by_length = prefixes.sort_by { |p| -p[:prefix].length }
    end
  end
end