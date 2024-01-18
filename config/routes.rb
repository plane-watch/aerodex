Rails.application.routes.draw do
  devise_for :users
  resources :aircraft
  root to: 'home#index'
end
