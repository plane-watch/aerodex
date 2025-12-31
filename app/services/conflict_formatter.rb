# frozen_string_literal: true

# Formats merge conflicts for display in console or logs.
#
# Provides structured output for reviewing data conflicts between sources,
# grouped by airport/entity and formatted for easy reading.
#
# @example Console output
#   conflicts = [...] # Array of conflict hashes from FieldMerger
#   ConflictFormatter.print(conflicts)
#
# @example Grouped by entity
#   ConflictFormatter.print(conflicts, group_by: :identifier)
class ConflictFormatter
  # Column widths for table output
  FIELD_WIDTH = 12
  SOURCE_WIDTH = 30
  VALUE_WIDTH = 40
  TRUST_WIDTH = 6

  class << self
    # Prints conflicts to STDOUT in a formatted table.
    #
    # @param conflicts [Array<Hash>] Conflict details from FieldMerger
    # @param group_by_identifier [Boolean] Whether to group conflicts by entity identifier
    # @param io [IO] Output stream (default: STDOUT)
    def print(conflicts, group_by_identifier: true, io: $stdout)
      return io.puts 'No conflicts to display.' if conflicts.empty?

      if group_by_identifier
        print_grouped(conflicts, io)
      else
        print_flat(conflicts, io)
      end

      io.puts
      io.puts summary(conflicts)
    end

    # Prints conflicts grouped by entity identifier (e.g., ICAO code).
    # Expects conflicts to have an :identifier key.
    #
    # @param conflicts [Array<Hash>] Conflict details with :identifier key
    # @param io [IO] Output stream (default: STDOUT)
    def print_grouped_by_identifier(conflicts, io: $stdout)
      return io.puts 'No conflicts to display.' if conflicts.empty?

      grouped = conflicts.group_by { |c| c[:identifier] || 'Unknown' }

      grouped.each do |identifier, entity_conflicts|
        io.puts
        io.puts "=== #{identifier} #{'=' * [0, 60 - identifier.to_s.length].max}"
        io.puts table_header
        io.puts '-' * total_width

        entity_conflicts.each do |conflict|
          print_conflict_row(conflict, io)
        end
      end

      io.puts
      io.puts summary(conflicts)
    end

    # Returns a summary string of conflict statistics.
    #
    # @param conflicts [Array<Hash>] Conflict details from FieldMerger
    # @return [String] Summary text
    def summary(conflicts)
      field_counts = conflicts.group_by { |c| c[:field] }.transform_values(&:count)
      source_counts = conflicts.flat_map { |c| c[:candidates].map { |s| s[:source_type] } }
                               .tally

      lines = []
      lines << "Total conflicts: #{conflicts.count}"
      lines << ''
      lines << 'By field:'
      field_counts.sort_by { |_, v| -v }.each do |field, count|
        lines << "  #{field}: #{count}"
      end
      lines << ''
      lines << 'By source:'
      source_counts.sort_by { |_, v| -v }.each do |source, count|
        lines << "  #{source}: #{count}"
      end

      lines.join("\n")
    end

    # Generates a hash suitable for storing conflicts in the database or JSON.
    #
    # @param conflicts [Array<Hash>] Conflict details from FieldMerger
    # @param identifier [Hash, String] The entity identifier (e.g., ICAO code)
    # @return [Hash] Structured conflict data
    def to_hash(conflicts, identifier: nil)
      {
        identifier: identifier,
        count: conflicts.count,
        by_field: conflicts.group_by { |c| c[:field] }.transform_values(&:count),
        conflicts: conflicts
      }
    end

    private

    # Prints conflicts grouped by entity identifier.
    def print_grouped(conflicts, io)
      # Group by the first source's identifiable attributes
      grouped = group_conflicts_by_entity(conflicts)

      grouped.each do |identifier, entity_conflicts|
        io.puts
        io.puts header_line(identifier)
        io.puts '-' * total_width

        entity_conflicts.each do |conflict|
          print_conflict_row(conflict, io)
        end
      end
    end

    # Prints conflicts in a flat list.
    def print_flat(conflicts, io)
      io.puts
      io.puts table_header
      io.puts '-' * total_width

      conflicts.each do |conflict|
        print_conflict_row(conflict, io)
      end
    end

    # Groups conflicts by entity identifier (extracts from source records).
    def group_conflicts_by_entity(conflicts)
      conflicts.group_by do |conflict|
        # Try to find an identifier from the source record
        source = conflict[:candidates].first&.dig(:source) ||
                 conflict.dig(:winner, :source)

        if source.respond_to?(:icao_code) && source.icao_code.present?
          source.icao_code
        elsif source.respond_to?(:iata_code) && source.iata_code.present?
          source.iata_code
        elsif source.respond_to?(:name)
          source.name
        else
          'Unknown'
        end
      end
    end

    def header_line(identifier)
      "=== #{identifier} ==="
    end

    def table_header
      format(
        "%-#{FIELD_WIDTH}s | %-#{SOURCE_WIDTH}s | %-#{VALUE_WIDTH}s | %#{TRUST_WIDTH}s",
        'Field', 'Source', 'Value', 'Trust'
      )
    end

    def total_width
      FIELD_WIDTH + SOURCE_WIDTH + VALUE_WIDTH + TRUST_WIDTH + 9 # separators
    end

    def print_conflict_row(conflict, io)
      field = conflict[:field]
      candidates = conflict[:candidates] || []
      winner = conflict[:winner]

      candidates.each_with_index do |candidate, idx|
        is_winner = winner && candidate[:source_type] == winner[:source_type]
        marker = is_winner ? '*' : ' '

        # Truncate and format value for display
        value_str = format_value(candidate[:value])
        source_name = candidate[:source_type].to_s.gsub('Source', '')

        row = format(
          "%s%-#{FIELD_WIDTH - 1}s | %-#{SOURCE_WIDTH}s | %-#{VALUE_WIDTH}s | %#{TRUST_WIDTH}d",
          marker,
          idx.zero? ? field : '',
          source_name,
          value_str,
          candidate[:trust_score] || 0
        )

        io.puts row
      end

      io.puts # Blank line between conflicts
    end

    def format_value(value)
      return '(nil)' if value.nil?

      str = value.to_s
      if str.length > VALUE_WIDTH
        "#{str[0, VALUE_WIDTH - 3]}..."
      else
        str
      end
    end
  end
end
