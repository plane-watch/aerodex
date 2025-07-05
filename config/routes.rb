Rails.application.routes.draw do
  devise_for :users
  resources :aircraft
  resources :operators
  root to: 'home#index'
end
