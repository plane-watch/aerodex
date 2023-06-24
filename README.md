# AERODEX

This is a WIP application/service for managing the Aerodex project.
The aerodex project is an initiative to create a free, open and reliable source of aviation information, such as Aircraft,
Flight Routes, Operators and more.

## Architecture
The application is a Ruby On Rails monolith, using a PostgreSQL database for storage and Meilisearch for search.

External Data Sources are implemented as a `Gateway`, which are classes that implement a common interface for fetching and transforming data into the Aerodex schema.


## Getting Started
TODO: Add instructions for getting started