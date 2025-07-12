Rails.application.routes.draw do
  devise_for :users
  resources :aircraft
  resources :aircraft_types, only: [:index]
  resources :manufacturers, only: [:index]
  resources :airports, only: [:index]
  resources :countries, only: [:index]
  resources :routes, only: [:index]
  resources :operators
  root to: 'home#index'
end
