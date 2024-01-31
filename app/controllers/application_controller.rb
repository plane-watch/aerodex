class ApplicationController < ActionController::Base
  include Pagy::Backend

  # Expect CSRF tokens to be passed with all post requests, if not raise an exception
  # use prepend: true to make sure this happens first before any other actions.
  protect_from_forgery with: :exception, prepend: true

  # Ensure that all actions require a user to be logged in
  before_action :authenticate_user!

  # Ensure that all we set the whodunnit in paper_trail to the current user
  before_action :set_paper_trail_whodunnit

end
