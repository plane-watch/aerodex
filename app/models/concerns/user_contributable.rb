module UserContributable
  extend ActiveSupport::Concern

  included do
    has_many :annotations, polymorphic: true, dependent: :destroy

    enum status: { inactive: 0, active: 1, flagged: 2, invalid: 3 }

    scope :active, -> { where(status: %w(active flagged_for_review)) }
    scope :inactive, -> { where(status: 'inactive') }
    scope :invalid, -> { where(status: 'invalid') }
    scope :flagged, -> { where(status: 'flagged') }
    scope :by_confidence, -> { order(confidence: :desc) }

    has_paper_trail
  end

  class_methods do

    def statuses_for_select
      statuses.keys.map { |status| [status.titleize, status] }
    end
    def activate!
      update(status: :active)
    end

    def deactivate!
      update(status: :inactive)
    end

    def flag!(reason)
      update(status: :flagged)
    end

  end
end