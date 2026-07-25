# frozen_string_literal: true

namespace :staged_batches do
  desc 'List pending batches'
  task pending: :environment do
    batches = StagedBatch.pending.recent

    if batches.empty?
      puts 'No pending batches.'
    else
      puts format('%-36s %-15s %-30s %s', 'ID', 'Entity', 'Created', 'Summary')
      puts '-' * 100
      batches.each do |batch|
        summary = "#{batch.summary['created'] || 0} created, #{batch.summary['updated'] || 0} updated"
        puts format('%-36s %-15s %-30s %s', batch.id, batch.entity_type, batch.created_at, summary)
      end
    end
  end

  desc 'Show batch details'
  task :show, [:batch_id] => :environment do |_t, args|
    batch = StagedBatch.find(args[:batch_id])

    puts "Batch: #{batch.id}"
    puts "Processor: #{batch.processor_type}"
    puts "Entity: #{batch.entity_type}"
    puts "Status: #{batch.status}"
    puts "Created: #{batch.created_at}"
    puts "Summary: #{batch.summary}"
    puts ''
    puts 'Changes (first 10):'
    batch.staged_changes.limit(10).each do |change|
      puts "  #{change.operation.upcase} #{change.record_type} #{change.record_identifier}"
      change.diff.each do |field, (old_val, new_val)|
        puts "    #{field}: #{old_val.inspect} -> #{new_val.inspect}"
      end
    end

    remaining = batch.staged_changes.count - 10
    puts "  ... and #{remaining} more" if remaining.positive?
  end

  desc 'Apply a pending batch'
  task :apply, [:batch_id] => :environment do |_t, args|
    batch = StagedBatch.find(args[:batch_id])

    abort "Batch is not pending (status: #{batch.status})" unless batch.pending?

    print "Apply #{batch.staged_changes.count} changes to #{batch.entity_type}? [y/N] "
    response = $stdin.gets.chomp.downcase

    if response == 'y'
      batch.apply!(by: nil)
      puts 'Applied successfully.'
    else
      puts 'Cancelled.'
    end
  end

  desc 'Reject a pending batch'
  task :reject, [:batch_id] => :environment do |_t, args|
    batch = StagedBatch.find(args[:batch_id])

    abort "Batch is not pending (status: #{batch.status})" unless batch.pending?

    print 'Reason (optional): '
    reason = $stdin.gets.chomp
    reason = nil if reason.blank?

    batch.reject!(by: nil, reason: reason)
    puts 'Batch rejected.'
  end

  desc 'List recent batches (all statuses)'
  task :history, [:limit] => :environment do |_t, args|
    limit = (args[:limit] || 20).to_i
    batches = StagedBatch.recent.limit(limit)

    puts format('%-36s %-15s %-12s %-20s %s', 'ID', 'Entity', 'Status', 'Created', 'Summary')
    puts '-' * 110
    batches.each do |batch|
      summary = "#{batch.summary['created'] || 0}c/#{batch.summary['updated'] || 0}u"
      puts format('%-36s %-15s %-12s %-20s %s', batch.id, batch.entity_type, batch.status,
                  batch.created_at.strftime('%Y-%m-%d %H:%M'), summary)
    end
  end
end
