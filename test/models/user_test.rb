# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id                       :integer          not null, primary key
#  first_name               :string
#  last_name                :string
#  email                    :string           default(""), not null
#  encrypted_password       :string           default(""), not null
#  reset_password_token     :string
#  reset_password_sent_at   :datetime
#  remember_created_at      :datetime
#  confirmation_token       :string
#  confirmed_at             :datetime
#  confirmation_sent_at     :datetime
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  contribution_trust_score :integer          default(50), not null
#  admin                    :boolean          default(FALSE), not null
#
# Indexes
#
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "admin? returns false by default" do
    user = User.new(email: "test@example.com", password: "password123")
    assert_not user.admin?
  end

  test "admin? returns true when admin flag is set" do
    user = User.new(email: "admin@example.com", password: "password123", admin: true)
    assert user.admin?
  end
end
