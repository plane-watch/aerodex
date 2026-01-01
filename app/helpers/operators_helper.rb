module OperatorsHelper
  include AircraftHelper

  def operator_logo_for(operator)

    # In Rails 8, we need to use Dir.glob to find assets matching the pattern

    matching_files = []
    if operator&.iata_code.present?
      logo_pattern = Rails.root.join('app', 'assets', 'images', 'airline_logos', "#{operator.iata_code}_*.png")
      matching_files = Dir.glob(logo_pattern)
    end

    if matching_files.any?
      # Get the filename without the full path
      filename = File.basename(matching_files.first)
      asset_path("airline_logos/#{filename}")
    else
      default_logo ||= File.basename(Rails.root.join('app', 'assets', 'images', 'airline_logos', 'default.png'))
      asset_path("airline_logos/#{default_logo}")
    end
  end
end
