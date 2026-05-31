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

ActiveRecord::Schema[8.1].define(version: 2026_05_31_041739) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "aircraft", force: :cascade do |t|
    t.string "aircraft_name"
    t.integer "aircraft_type_id"
    t.string "cabin_configuration"
    t.datetime "created_at", null: false
    t.integer "engine_count"
    t.string "engine_model"
    t.jsonb "field_provenance", default: {}, null: false
    t.string "icao"
    t.datetime "last_combined_at"
    t.integer "manufacture_year"
    t.string "model"
    t.integer "operator_id"
    t.string "owner"
    t.string "registration"
    t.bigint "registration_country_id", null: false
    t.date "registration_date"
    t.string "serial_number"
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.index ["aircraft_type_id"], name: "index_aircraft_on_aircraft_type_id"
    t.index ["operator_id"], name: "index_aircraft_on_operator_id"
    t.index ["registration_country_id"], name: "index_aircraft_on_registration_country_id"
  end

  create_table "aircraft_sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.integer "engine_count"
    t.string "engine_model"
    t.boolean "excluded", default: false, null: false
    t.datetime "excluded_at"
    t.string "excluded_by"
    t.string "exclusion_reason"
    t.string "icao", null: false, comment: "Mode S hex code (24-bit transponder address)"
    t.datetime "import_date", null: false
    t.integer "manufacture_year"
    t.string "manufacturer_code", comment: "ICAO manufacturer code"
    t.string "model"
    t.string "operator_icao"
    t.string "operator_name"
    t.string "owner"
    t.string "registration", null: false
    t.string "registration_country_code", comment: "ISO 2-char country code"
    t.date "registration_date"
    t.string "serial_number"
    t.string "status"
    t.string "type", null: false
    t.string "type_code", comment: "ICAO aircraft type designator"
    t.datetime "updated_at", null: false
    t.index ["data"], name: "index_aircraft_sources_on_data", using: :gin
    t.index ["excluded"], name: "index_aircraft_sources_on_excluded"
    t.index ["icao", "type"], name: "index_aircraft_sources_on_icao_and_type", unique: true
    t.index ["icao"], name: "index_aircraft_sources_on_icao"
    t.index ["registration"], name: "index_aircraft_sources_on_registration"
    t.index ["type"], name: "index_aircraft_sources_on_type"
  end

  create_table "aircraft_type_sources", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.string "engine_type"
    t.integer "engines"
    t.boolean "excluded", default: false, null: false
    t.datetime "excluded_at"
    t.string "excluded_by"
    t.string "exclusion_reason"
    t.string "iata_code"
    t.datetime "import_date", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "manufacturer"
    t.string "name"
    t.string "type"
    t.string "type_code"
    t.datetime "updated_at", null: false
    t.string "wtc"
    t.index ["excluded"], name: "index_aircraft_type_sources_on_excluded"
    t.index ["iata_code", "type"], name: "index_aircraft_type_sources_on_iata_and_type"
  end

  create_table "aircraft_types", force: :cascade do |t|
    t.integer "aircraft_count", default: 0, null: false
    t.integer "category", limit: 2
    t.datetime "created_at", null: false
    t.string "engine_type"
    t.integer "engines"
    t.jsonb "field_provenance", default: {}, null: false
    t.datetime "last_combined_at"
    t.integer "manufacturer_id"
    t.string "name"
    t.string "type_code"
    t.datetime "updated_at", null: false
    t.string "wtc"
    t.index ["manufacturer_id"], name: "index_aircraft_types_on_manufacturer_id"
    t.index ["type_code", "name"], name: "index_aircraft_types_on_type_code_and_name", unique: true
  end

  create_table "airport_runways", force: :cascade do |t|
    t.integer "airport_id"
    t.boolean "closed", default: false
    t.datetime "created_at", null: false
    t.jsonb "field_provenance", default: {}, null: false
    t.string "he_ident"
    t.decimal "heading"
    t.datetime "last_combined_at"
    t.string "le_ident"
    t.decimal "length"
    t.boolean "lighted", default: false
    t.string "runway_name"
    t.string "surface"
    t.datetime "updated_at", null: false
    t.decimal "width"
  end

  create_table "airport_sources", force: :cascade do |t|
    t.string "airport_type"
    t.string "city"
    t.string "country_code"
    t.datetime "created_at", null: false
    t.jsonb "data", default: "{}", null: false
    t.decimal "elevation"
    t.boolean "excluded", default: false, null: false
    t.datetime "excluded_at"
    t.string "excluded_by"
    t.string "exclusion_reason"
    t.string "iata_code"
    t.string "icao_code"
    t.string "ident"
    t.datetime "import_date", null: false
    t.decimal "latitude", precision: 9, scale: 6
    t.decimal "longitude", precision: 9, scale: 6
    t.string "municipality"
    t.string "name", null: false
    t.string "timezone"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["data"], name: "index_airport_sources_on_data", using: :gin
    t.index ["excluded"], name: "index_airport_sources_on_excluded"
    t.index ["iata_code", "type"], name: "index_airport_sources_on_iata_and_type"
    t.index ["icao_code", "type"], name: "index_airport_sources_on_icao_and_type"
    t.index ["ident", "type"], name: "index_airport_sources_on_ident_and_type"
  end

  create_table "airports", force: :cascade do |t|
    t.integer "airport_runways_count", default: 0, null: false
    t.decimal "altitude"
    t.string "city"
    t.string "country"
    t.bigint "country_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "field_provenance", default: {}, null: false
    t.integer "flight_information_region_id"
    t.string "iata_code"
    t.string "icao_code"
    t.datetime "last_combined_at"
    t.decimal "latitude", precision: 9, scale: 6
    t.decimal "longitude", precision: 9, scale: 6
    t.string "name"
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.string "wmo_code"
    t.index ["country_id"], name: "index_airports_on_country_id"
  end

  create_table "countries", force: :cascade do |t|
    t.integer "airports_count", default: 0, null: false
    t.string "capital"
    t.datetime "created_at", null: false
    t.jsonb "field_provenance", default: {}, null: false
    t.string "iso_2char_code"
    t.string "iso_3char_code"
    t.string "iso_num_code"
    t.datetime "last_combined_at"
    t.string "name"
    t.integer "operators_count", default: 0, null: false
    t.datetime "updated_at", null: false
  end

  create_table "country_sources", force: :cascade do |t|
    t.string "capital"
    t.datetime "created_at", null: false
    t.jsonb "data", default: "{}", null: false
    t.boolean "excluded", default: false, null: false
    t.datetime "excluded_at"
    t.string "excluded_by"
    t.string "exclusion_reason"
    t.datetime "import_date", null: false
    t.string "iso_2char_code"
    t.string "iso_3char_code"
    t.string "iso_num_code"
    t.string "name"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["excluded"], name: "index_country_sources_on_excluded"
  end

  create_table "flight_information_regions", force: :cascade do |t|
    t.polygon "bounds"
    t.bigint "country_id", null: false
    t.datetime "created_at", null: false
    t.string "icao_code"
    t.string "region"
    t.datetime "updated_at", null: false
    t.index ["country_id"], name: "index_flight_information_regions_on_country_id"
  end

  create_table "manufacturer_sources", force: :cascade do |t|
    t.jsonb "alt_names"
    t.string "country"
    t.datetime "created_at", null: false
    t.jsonb "data", default: "{}", null: false
    t.boolean "excluded", default: false, null: false
    t.datetime "excluded_at"
    t.string "excluded_by"
    t.string "exclusion_reason"
    t.string "icao_code", null: false
    t.datetime "import_date", null: false
    t.string "name", null: false
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["excluded"], name: "index_manufacturer_sources_on_excluded"
  end

  create_table "manufacturers", force: :cascade do |t|
    t.integer "aircraft_count", default: 0, null: false
    t.integer "aircraft_types_count", default: 0, null: false
    t.jsonb "alt_names"
    t.bigint "country_id"
    t.datetime "created_at", null: false
    t.jsonb "field_provenance", default: {}, null: false
    t.string "icao_code"
    t.datetime "last_combined_at"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["country_id"], name: "index_manufacturers_on_country_id"
  end

  create_table "operator_match_decisions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "decided_by"
    t.integer "decision_type", default: 0, null: false
    t.string "matched_icao_code"
    t.string "matched_name", null: false
    t.text "notes"
    t.bigint "operator_id", null: false
    t.datetime "updated_at", null: false
    t.index ["matched_icao_code"], name: "index_operator_match_decisions_on_matched_icao_code"
    t.index ["matched_name", "matched_icao_code"], name: "idx_match_decisions_unique_name_icao", unique: true
    t.index ["matched_name"], name: "index_operator_match_decisions_on_matched_name"
    t.index ["operator_id"], name: "index_operator_match_decisions_on_operator_id"
  end

  create_table "operator_sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "data", default: "{}", null: false
    t.boolean "excluded", default: false, null: false
    t.datetime "excluded_at"
    t.string "excluded_by"
    t.string "exclusion_reason"
    t.string "iata_code"
    t.string "icao_code"
    t.datetime "import_date", null: false
    t.string "name"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["data"], name: "index_operator_sources_on_data", using: :gin
    t.index ["excluded"], name: "index_operator_sources_on_excluded"
  end

  create_table "operators", force: :cascade do |t|
    t.integer "aircraft_count", default: 0, null: false
    t.string "country"
    t.bigint "country_id"
    t.datetime "created_at", null: false
    t.jsonb "field_provenance", default: {}, null: false
    t.string "iata_code"
    t.string "icao_code"
    t.datetime "last_combined_at"
    t.string "name"
    t.bigint "parent_operator_id"
    t.datetime "updated_at", null: false
    t.index ["country_id"], name: "index_operators_on_country_id"
    t.index ["parent_operator_id"], name: "index_operators_on_parent_operator_id"
  end

  create_table "route_segments", force: :cascade do |t|
    t.integer "airport_id"
    t.time "arrival_time"
    t.datetime "created_at", null: false
    t.time "departing_time"
    t.integer "order"
    t.integer "route_id"
    t.datetime "updated_at", null: false
    t.index ["airport_id"], name: "index_route_segments_on_airport_id"
    t.index ["route_id"], name: "index_route_segments_on_route_id"
  end

  create_table "route_sources", force: :cascade do |t|
    t.string "airline_code", null: false
    t.string "airport_codes", null: false
    t.string "callsign", null: false
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.boolean "excluded", default: false, null: false
    t.datetime "excluded_at"
    t.string "excluded_by"
    t.string "exclusion_reason"
    t.datetime "import_date", null: false
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["airline_code"], name: "index_route_sources_on_airline_code"
    t.index ["callsign", "type"], name: "index_route_sources_on_callsign_and_type", unique: true
    t.index ["data"], name: "index_route_sources_on_data", using: :gin
    t.index ["excluded"], name: "index_route_sources_on_excluded"
  end

  create_table "routes", force: :cascade do |t|
    t.string "call_sign"
    t.datetime "created_at", null: false
    t.bigint "operator_id", null: false
    t.integer "route_segments_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["operator_id", "call_sign"], name: "index_routes_on_operator_id_and_call_sign", unique: true
    t.index ["operator_id"], name: "index_routes_on_operator_id"
  end

  create_table "runway_sources", force: :cascade do |t|
    t.string "airport_ident", null: false
    t.boolean "closed", default: false
    t.datetime "created_at", null: false
    t.jsonb "data", default: "{}", null: false
    t.boolean "excluded", default: false, null: false
    t.datetime "excluded_at"
    t.string "excluded_by"
    t.string "exclusion_reason"
    t.decimal "he_displaced_threshold_ft"
    t.decimal "he_elevation_ft"
    t.decimal "he_heading_deg"
    t.string "he_ident"
    t.decimal "he_latitude", precision: 9, scale: 6
    t.decimal "he_longitude", precision: 9, scale: 6
    t.datetime "import_date", null: false
    t.decimal "le_displaced_threshold_ft"
    t.decimal "le_elevation_ft"
    t.decimal "le_heading_deg"
    t.string "le_ident"
    t.decimal "le_latitude", precision: 9, scale: 6
    t.decimal "le_longitude", precision: 9, scale: 6
    t.decimal "length_ft"
    t.boolean "lighted", default: false
    t.string "surface"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.decimal "width_ft"
    t.index ["airport_ident", "le_ident", "type"], name: "index_runway_sources_on_airport_le_ident_type", unique: true
    t.index ["airport_ident"], name: "index_runway_sources_on_airport_ident"
    t.index ["data"], name: "index_runway_sources_on_data", using: :gin
    t.index ["excluded"], name: "index_runway_sources_on_excluded"
  end

  create_table "source_changes", force: :cascade do |t|
    t.string "changed"
    t.datetime "created_at", null: false
    t.string "type"
    t.datetime "updated_at", null: false
  end

  create_table "source_import_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "import_errors"
    t.string "importer_type"
    t.integer "records_processed"
    t.boolean "success"
    t.datetime "updated_at", null: false
  end

  create_table "source_trust_scores", force: :cascade do |t|
    t.integer "base_trust", default: 50, null: false
    t.datetime "created_at", null: false
    t.string "entity_type", null: false
    t.string "field_name"
    t.string "source_type", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_type", "source_type", "field_name"], name: "idx_source_trust_scores_unique", unique: true
  end

  create_table "staged_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "applied_at"
    t.integer "apply_progress", default: 0
    t.integer "apply_total"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "entity_type", null: false
    t.text "error_message"
    t.string "job_id"
    t.text "notes"
    t.integer "processing_progress", default: 0
    t.integer "processing_total"
    t.string "processor_type", null: false
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.jsonb "summary", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_staged_batches_on_created_at"
    t.index ["created_by_id"], name: "index_staged_batches_on_created_by_id"
    t.index ["entity_type"], name: "index_staged_batches_on_entity_type"
    t.index ["job_id"], name: "index_staged_batches_on_job_id"
    t.index ["reviewed_by_id"], name: "index_staged_batches_on_reviewed_by_id"
    t.index ["status"], name: "index_staged_batches_on_status"
  end

  create_table "staged_changes", force: :cascade do |t|
    t.datetime "applied_at"
    t.datetime "created_at", null: false
    t.jsonb "diff", default: {}, null: false
    t.integer "operation", null: false
    t.bigint "record_id"
    t.string "record_identifier", null: false
    t.string "record_type", null: false
    t.uuid "staged_batch_id", null: false
    t.index ["record_identifier"], name: "index_staged_changes_on_record_identifier"
    t.index ["record_type", "record_id"], name: "index_staged_changes_on_record_type_and_record_id"
    t.index ["staged_batch_id", "applied_at"], name: "index_staged_changes_on_staged_batch_id_and_applied_at"
    t.index ["staged_batch_id"], name: "index_staged_changes_on_staged_batch_id"
  end

  create_table "user_contributions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.string "entity_type", null: false
    t.string "field_name", null: false
    t.jsonb "new_value"
    t.text "notes"
    t.jsonb "old_value"
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["entity_type", "entity_id", "field_name"], name: "idx_user_contributions_entity"
    t.index ["reviewed_by_id"], name: "index_user_contributions_on_reviewed_by_id"
    t.index ["status"], name: "index_user_contributions_on_status"
    t.index ["user_id"], name: "index_user_contributions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.integer "contribution_trust_score", default: 50, null: false
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name"
    t.string "last_name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.text "object"
    t.text "object_changes"
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "aircraft", "countries", column: "registration_country_id"
  add_foreign_key "airports", "countries"
  add_foreign_key "flight_information_regions", "countries"
  add_foreign_key "manufacturers", "countries"
  add_foreign_key "operator_match_decisions", "operators"
  add_foreign_key "operators", "countries"
  add_foreign_key "operators", "operators", column: "parent_operator_id"
  add_foreign_key "routes", "operators"
  add_foreign_key "staged_batches", "users", column: "created_by_id"
  add_foreign_key "staged_batches", "users", column: "reviewed_by_id"
  add_foreign_key "staged_changes", "staged_batches"
  add_foreign_key "user_contributions", "users"
  add_foreign_key "user_contributions", "users", column: "reviewed_by_id"
end
