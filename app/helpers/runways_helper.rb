# frozen_string_literal: true

module RunwaysHelper
  # Returns the display name for a runway surface.
  #
  # Handles both normalised keys (e.g., "asphalt") stored in the database
  # and raw values that haven't been normalised yet.
  #
  # @param surface [String, nil] The surface value (normalised key or raw)
  # @return [String] The human-readable surface name
  def surface_display_name(surface)
    return 'Unknown' if surface.blank?

    # Check if the value is already a normalised key
    key = surface.to_sym
    if RunwaySurfaceNormaliser::SURFACE_TYPES.key?(key)
      RunwaySurfaceNormaliser::SURFACE_TYPES[key]
    else
      # Fall back to normalising raw values
      RunwaySurfaceNormaliser.display_name(surface)
    end
  end
end