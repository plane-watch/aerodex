Rails.application.routes.draw do
  devise_for :users

  # Search autocomplete suggestions API
  get 'search/suggestions', to: 'search_suggestions#index', as: :search_suggestions

  resources :aircraft
  resources :aircraft_types, only: [:index, :show]
  resources :manufacturers, only: [:index, :show]
  resources :airports, only: [:index, :show]
  resources :runways, only: [:index]
  resources :countries, only: [:index, :show]
  resources :routes, only: [:index, :show]
  resources :operators
  get 'dashboard', to: 'home#dashboard'
  root to: 'home#dashboard'
end
