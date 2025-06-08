require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Aerodex
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))
    config.autoload_paths << Rails.root.join('app', 'processor')
    config.eager_load_paths << Rails.root.join('app', 'processor')

    # Add Zeitwerk debugging inside the configuration block
    if Rails.env.development?
      # Enable Zeitwerk debugging
      config.autoloader = :zeitwerk

      # Print autoload paths and debug information
      config.after_initialize do
        puts "\nAutoload paths:"
        Rails.autoloaders.main.dirs.each do |dir|
          puts "  #{dir}"
        end

        # Set up logging for Zeitwerk
        Rails.autoloaders.main.on_load do |cpath, value, abspath|
          puts "Loaded: #{cpath} from #{abspath}"
        end
      end
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
