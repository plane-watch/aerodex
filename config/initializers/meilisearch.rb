# frozen_string_literal: true

MeiliSearch::Rails.configuration = {
  meilisearch_url: ENV.fetch('MEILISEARCH_URL', 'http://localhost:7700'),
  meilisearch_api_key: ENV['MEILI_MASTER_KEY']
}
