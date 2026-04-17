# frozen_string_literal: true

module Search
  # Registry of searchable fields derived from model Meilisearch configurations.
  #
  # This dynamically reads filterable_attributes from each model's meilisearch
  # configuration, eliminating the need for manual registration.
  #
  # @example Getting fields for a model
  #   fields = FieldRegistry.fields_for('Aircraft')
  #   # => [:icao, :registration, :manufacturer, ...]
  #
  # @example Checking if a field is valid
  #   FieldRegistry.valid_field?('Aircraft', 'manufacturer')  # => true
  #   FieldRegistry.valid_field?('Aircraft', 'bogus')         # => false
  class FieldRegistry
    # Models that support field-specific search.
    # These must include MeiliSearch::Rails and define filterable_attributes.
    SEARCHABLE_MODELS = %w[
      Aircraft
      AircraftType
      Operator
      Airport
      Manufacturer
      Country
      Route
    ].freeze

    class << self
      # Returns all filterable field names for a given model.
      #
      # @param model_name [String] The model class name
      # @return [Array<Symbol>] Array of field names
      def fields_for(model_name)
        model_class = model_name.safe_constantize
        return [] unless model_class&.respond_to?(:meilisearch_settings)

        settings = model_class.meilisearch_settings
        return [] unless settings

        settings.get_setting(:filterableAttributes) || []
      rescue StandardError
        []
      end

      # Returns an array of field names as strings for a model.
      #
      # @param model_name [String] The model class name
      # @return [Array<String>]
      def field_names_for(model_name)
        fields_for(model_name).map(&:to_s)
      end

      # Returns the Meilisearch attribute name for a user-facing field name.
      # Since we use the same names, this just validates and returns the field.
      #
      # @param model_name [String] The model class name
      # @param field_name [String, Symbol] The field name
      # @return [String, nil] The Meilisearch attribute name, or nil if not found
      def meilisearch_attribute_for(model_name, field_name)
        field_sym = field_name.to_sym
        return field_name.to_s if fields_for(model_name).include?(field_sym)

        nil
      end

      # Checks if a field name is valid for a model.
      #
      # @param model_name [String] The model class name
      # @param field_name [String, Symbol] The field name to validate
      # @return [Boolean]
      def valid_field?(model_name, field_name)
        fields_for(model_name).include?(field_name.to_sym)
      end

      # Returns field suggestions matching a prefix, for autocomplete.
      #
      # @param model_name [String] The model class name
      # @param prefix [String] The prefix to match against field names
      # @return [Array<Hash>] Array of { value:, display: } hashes
      def suggest_fields(model_name, prefix)
        prefix = prefix.to_s.downcase

        fields_for(model_name)
          .select { |name| name.to_s.start_with?(prefix) }
          .map do |name|
            {
              value: name.to_s,
              display: humanize_field_name(name)
            }
          end
          .sort_by { |suggestion| suggestion[:value] }
      end

      # Returns all registered model names.
      #
      # @return [Array<String>]
      def registered_models
        SEARCHABLE_MODELS
      end

      private

      # Converts a field name to a human-readable display name.
      #
      # @param field_name [Symbol, String] The field name
      # @return [String] Human-readable name
      def humanize_field_name(field_name)
        field_name.to_s.titleize
      end
    end
  end
end
