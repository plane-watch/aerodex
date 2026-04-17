# frozen_string_literal: true

module Admin
  # Base controller for all admin controllers.
  # Ensures only users with the admin flag can access admin pages.
  class BaseController < ApplicationController
    before_action :require_admin!

    private

    # Redirects non-admin users to the root path with an alert.
    def require_admin!
      return if current_user&.admin?

      redirect_to root_path, alert: "You don't have permission to access this area."
    end
  end
end
