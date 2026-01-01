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
#
# Indexes
#
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#

class User < ApplicationRecord
  # The minimum trust score required to be considered a trusted contributor.
  # Trusted contributors may have their contributions auto-approved.
  TRUSTED_CONTRIBUTOR_THRESHOLD = 90

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable

  has_many :user_contributions, dependent: :destroy
  has_many :reviewed_contributions,
           class_name: 'UserContribution',
           foreign_key: :reviewed_by_id,
           inverse_of: :reviewed_by,
           dependent: :nullify

  # Returns the user's full name.
  #
  # @return [String]
  def name
    "#{first_name} #{last_name}"
  end

  # Checks if the user has earned trusted contributor status.
  # Trusted contributors may have their data corrections auto-approved.
  #
  # @return [Boolean]
  def trusted_contributor?
    contribution_trust_score >= TRUSTED_CONTRIBUTOR_THRESHOLD
  end

  # Returns the number of approved contributions by this user.
  #
  # @return [Integer]
  def approved_contributions_count
    user_contributions.approved.count
  end
end
