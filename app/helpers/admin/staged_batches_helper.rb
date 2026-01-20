# frozen_string_literal: true

module Admin
  # Helper methods for staged batches views.
  module StagedBatchesHelper
    # Returns Tailwind classes for a status badge.
    #
    # @param status [String] The batch status
    # @return [String] Tailwind CSS classes
    def status_badge_classes(status)
      base = "inline-flex items-center rounded-md px-2 py-1 text-xs font-medium ring-1 ring-inset"

      colour = case status
               when "pending"
                 "bg-yellow-50 text-yellow-800 ring-yellow-600/20"
               when "applied"
                 "bg-green-50 text-green-700 ring-green-600/20"
               when "rejected", "failed"
                 "bg-red-50 text-red-700 ring-red-600/20"
               when "processing"
                 "bg-blue-50 text-blue-700 ring-blue-600/20"
               when "rolled_back", "superseded"
                 "bg-gray-50 text-gray-600 ring-gray-500/10"
               else
                 "bg-gray-50 text-gray-600 ring-gray-500/10"
               end

      "#{base} #{colour}"
    end

    # Formats a batch summary hash into a human-readable string.
    #
    # @param summary [Hash] The summary hash with created/updated counts
    # @return [String] Formatted summary
    def format_batch_summary(summary)
      return "No changes" if summary.blank?

      parts = []
      parts << "#{summary['created']} created" if summary["created"].to_i.positive?
      parts << "#{summary['updated']} updated" if summary["updated"].to_i.positive?
      parts.empty? ? "No changes" : parts.join(", ")
    end
  end
end
