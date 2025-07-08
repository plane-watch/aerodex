# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_07_08_095203) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "aircraft", force: :cascade do |t|
    t.string "icao"
    t.integer "aircraft_type_id"
    t.string "serial_number"
    t.integer "manufacture_year"
    t.string "owner"
    t.integer "operator_id"
    t.string "registration"
    t.date "registration_date"
    t.integer "engine_count"
    t.string "engine_model"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "cabin_configuration"
    t.string "aircraft_name"
    t.integer "status", default: 0
    t.string "model"
    t.bigint "registration_country_id", null: false
    t.index ["aircraft_type_id"], name: "index_aircraft_on_aircraft_type_id"
    t.index ["operator_id"], name: "index_aircraft_on_operator_id"
    t.index ["registration_country_id"], name: "index_aircraft_on_registration_country_id"
  end

  create_table "aircraft_type_sources", force: :cascade do |t|
    t.string "name"
    t.string "type_code"
    t.string "manufacturer"
    t.string "wtc"
    t.string "category"
    t.integer "engines"
    t.string "engine_type"
    t.string "type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "aircraft_types", force: :cascade do |t|
    t.integer "manufacturer_id"
    t.string "type_code"
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "category", limit: 2
    t.string "wtc"
    t.integer "engines"
    t.string "engine_type"
    t.index ["manufacturer_id"], name: "index_aircraft_types_on_manufacturer_id"
  end

  create_table "airport_runways", force: :cascade do |t|
    t.integer "airport_id"
    t.string "runway_name"
    t.decimal "heading"
    t.decimal "length"
    t.decimal "width"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "airports", force: :cascade do |t|
    t.string "name"
    t.string "city"
    t.string "country"
    t.string "iata_code"
    t.string "icao_code"
    t.string "wmo_code"
    t.integer "flight_information_region_id"
    t.decimal "latitude", precision: 9, scale: 6
    t.decimal "longitude", precision: 9, scale: 6
    t.decimal "altitude"
    t.string "timezone"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "country_id", null: false
    t.index ["country_id"], name: "index_airports_on_country_id"
  end

  create_table "countries", force: :cascade do |t|
    t.string "iso_2char_code"
    t.string "iso_3char_code"
    t.string "iso_num_code"
    t.string "name"
    t.string "capital"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "country_sources", force: :cascade do |t|
    t.string "iso_2char_code"
    t.string "iso_3char_code"
    t.string "iso_num_code"
    t.string "name"
    t.string "capital"
    t.string "type"
    t.datetime "import_date", null: false
    t.jsonb "data", default: "{}", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "flight_information_regions", force: :cascade do |t|
    t.string "icao_code"
    t.string "country"
    t.string "region"
    t.polygon "bounds"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "country_id", null: false
    t.index ["country_id"], name: "index_flight_information_regions_on_country_id"
  end

  create_table "manufacturer_sources", force: :cascade do |t|
    t.string "name", null: false
    t.string "icao_code", null: false
    t.string "type", null: false
    t.string "country"
    t.datetime "import_date", null: false
    t.jsonb "data", default: "{}", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "alt_names"
  end

  create_table "manufacturers", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "icao_code"
    t.jsonb "alt_names"
    t.bigint "country_id"
    t.index ["country_id"], name: "index_manufacturers_on_country_id"
  end

  create_table "operator_sources", force: :cascade do |t|
    t.string "icao_code"
    t.string "iata_code"
    t.string "name"
    t.string "type", null: false
    t.datetime "import_date", null: false
    t.jsonb "data", default: "{}", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["data"], name: "index_operator_sources_on_data", using: :gin
  end

  create_table "operators", force: :cascade do |t|
    t.string "name"
    t.string "icao_code"
    t.string "iata_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "country_id"
    t.index ["country_id"], name: "index_operators_on_country_id"
  end

  create_table "route_segments", force: :cascade do |t|
    t.integer "route_id"
    t.integer "airport_id"
    t.integer "order"
    t.time "arrival_time"
    t.time "departing_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["airport_id"], name: "index_route_segments_on_airport_id"
    t.index ["route_id"], name: "index_route_segments_on_route_id"
  end

  create_table "routes", force: :cascade do |t|
    t.string "call_sign"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "operator_id", null: false
    t.index ["operator_id"], name: "index_routes_on_operator_id"
  end

  create_table "source_changes", force: :cascade do |t|
    t.string "type"
    t.string "changed"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "source_import_reports", force: :cascade do |t|
    t.string "importer_type"
    t.jsonb "import_errors"
    t.integer "records_processed"
    t.boolean "success"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.string "item_type", null: false
    t.bigint "item_id", null: false
    t.string "event", null: false
    t.string "whodunnit"
    t.text "object"
    t.datetime "created_at"
    t.text "object_changes"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "aircraft", "countries", column: "registration_country_id"
  add_foreign_key "airports", "countries"
  add_foreign_key "flight_information_regions", "countries"
  add_foreign_key "manufacturers", "countries"
  add_foreign_key "operators", "countries"
  add_foreign_key "routes", "operators"
end
