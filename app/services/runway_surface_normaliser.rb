# frozen_string_literal: true

# Normalises runway surface descriptions to canonical types.
# The source data contains hundreds of variations (ASPH, ASP, Asphalt, asphalt, etc.)
# which this service maps to a consistent set of surface types.
class RunwaySurfaceNormaliser
  # Canonical surface types with their display names
  SURFACE_TYPES = {
    asphalt: 'Asphalt',
    concrete: 'Concrete',
    asphalt_concrete: 'Asphalt/Concrete',
    grass: 'Grass',
    gravel: 'Gravel',
    dirt: 'Dirt',
    sand: 'Sand',
    water: 'Water',
    ice: 'Ice',
    snow: 'Snow',
    coral: 'Coral',
    clay: 'Clay',
    bituminous: 'Bituminous',
    turf: 'Turf',
    metal: 'Metal',
    paved: 'Paved',
    unpaved: 'Unpaved',
    unknown: 'Unknown'
  }.freeze

  # Patterns mapped to canonical types (order matters - more specific patterns first)
  PATTERNS = [
    # Combined surfaces
    [/asph.*conc|conc.*asph|asp.*con|con.*asp/i, :asphalt_concrete],

    # Asphalt variations
    [/\A'?asph|asphal|aspal|ashp|^asp\b|^a$/i, :asphalt],

    # Concrete variations
    [/concr|^conc|^con\b|^cem|cement|^c$/i, :concrete],

    # Grass variations
    [/grass|grassed|gras{1,2}|^grs\b|^gr\b|herbe|sod/i, :grass],

    # Turf (similar to grass but distinct)
    [/\bturf\b/i, :turf],

    # Gravel variations
    [/gravel|^grvl|^grv\b|^gvl\b|crushed rock|cinders|shale|hardcore/i, :gravel],

    # Dirt/Earth variations
    [/\bdirt\b|earth|soil|ground|loam|murram/i, :dirt],

    # Coral (must come before sand to catch "Coral sand")
    [/coral/i, :coral],

    # Sand
    [/\bsand\b|^san\b/i, :sand],

    # Water (seaplane bases)
    [/\bwater\b/i, :water],

    # Ice
    [/\bice\b/i, :ice],

    # Snow
    [/\bsnow\b|^sno\b/i, :snow],

    # Clay
    [/\bclay\b|^cla\b/i, :clay],

    # Bituminous/Tar/Macadam
    [/bitum|^bit\b|^tar\b|tarmac|macadam|^mac\b/i, :bituminous],

    # Metal (PSP - Pierced Steel Planking, etc.)
    [/\bmetal\b|^met\b|^mtal\b|^psp\b|steel/i, :metal],

    # Unpaved (must come before paved to catch "not paved", "unpaved")
    [/unpaved|not paved/i, :unpaved],

    # Paved (generic)
    [/\bpaved\b|sealed|^pem\b|^per\b/i, :paved]
  ].freeze

  class << self
    # Normalises a surface string to a canonical type symbol.
    #
    # @param surface [String, nil] The raw surface description
    # @return [Symbol] The canonical surface type
    def normalise(surface)
      return :unknown if surface.blank?

      cleaned = surface.to_s.strip

      # Check against patterns
      PATTERNS.each do |pattern, type|
        return type if cleaned.match?(pattern)
      end

      :unknown
    end

    # Returns the human-readable display name for a surface.
    #
    # @param surface [String, nil] The raw surface description
    # @return [String] The display name
    def display_name(surface)
      type = normalise(surface)
      SURFACE_TYPES[type]
    end

    # Returns the canonical type symbol and display name.
    #
    # @param surface [String, nil] The raw surface description
    # @return [Hash] Hash with :type and :display_name keys
    def normalise_with_display(surface)
      type = normalise(surface)
      { type: type, display_name: SURFACE_TYPES[type] }
    end

    # Batch normalise an array of surfaces, returning unique canonical types.
    #
    # @param surfaces [Array<String>] Array of raw surface descriptions
    # @return [Hash] Hash mapping raw values to their canonical types
    def batch_normalise(surfaces)
      surfaces.compact.uniq.each_with_object({}) do |surface, hash|
        hash[surface] = normalise(surface)
      end
    end
  end
end