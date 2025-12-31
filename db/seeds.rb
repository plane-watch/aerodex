# frozen_string_literal: true

# This file contains the record creation needed to seed the database with its default values.
# The data can be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# =============================================================================
# Source Trust Scores
# =============================================================================
# These scores provide database-level overrides for the defaults in SourceConfig.
# They allow administrators to fine-tune trust scores without code changes.
#
# Note: These values mirror SourceConfig defaults initially. Modify these to
# customise trust scores for your deployment.


# =============================================================================
# Countries (from ISO 3166)
# =============================================================================
# Sync countries from the ISO 3166 standard

puts 'Syncing countries from ISO 3166...'
Country.sync_from_iso3166!
puts "Synced #{Country.count} countries"

puts 'Seeding complete!'