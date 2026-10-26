# frozen_string_literal: true

Rails.application.routes.draw do
  # Health check endpoint used by container orchestrators to probe liveness.
  # Referenced by `config.silence_healthcheck_path` in the production
  # environment, so that these probes do not clog the logs.
  get 'up' => 'rails/health#show', as: :rails_health_check

  devise_for :users

  # Search autocomplete suggestions API
  get 'search/suggestions', to: 'search_suggestions#index', as: :search_suggestions

  # Admin namespace
  namespace :admin do
    resources :staged_batches, only: %i[index show] do
      member do
        post :apply
        post :reject
        post :rollback
        get :status
      end
    end
    resources :processors, only: %i[index create]
  end

  resources :aircraft
  resources :aircraft_types, only: %i[index show]
  resources :manufacturers, only: %i[index show]
  resources :airports, only: %i[index show]
  resources :runways, only: [:index]
  resources :countries, only: %i[index show]
  resources :routes, only: %i[index show]
  resources :operators
  get 'dashboard', to: 'home#dashboard'
  root to: 'home#dashboard'
end
