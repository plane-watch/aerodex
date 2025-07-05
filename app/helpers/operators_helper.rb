module OperatorsHelper
  def operator_logo_for(operator)
    return nil unless operator&.iata_code.present?

    # In Rails 8, we need to use Dir.glob to find assets matching the pattern
    logo_pattern = Rails.root.join('app', 'assets', 'images', 'airline_logos', "#{operator.iata_code}_*.png")
    matching_files = Dir.glob(logo_pattern)

    if matching_files.any?
      # Get the filename without the full path
      filename = File.basename(matching_files.first)
      asset_path("airline_logos/#{filename}")
    else
      nil
    end
  end
end
