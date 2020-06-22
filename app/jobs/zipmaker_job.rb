# frozen_string_literal: true

# Responsibilities:
# If needed, zip files to zip storage and calculate checksum(s).
# Otherwise, touch the existing main ".zip" file to freshen it in cache.
# Invoke PlexerJob for each zip part.
class ZipmakerJob < ApplicationJob
  queue_as :zipmaker
  delegate :create_zip!, :file_path, :part_keys, to: :zip

  attr_accessor :zip

  before_perform do |job|
    job.zip = DruidVersionZip.new(job.arguments.first, job.arguments.second, job.arguments.third)
  end

  # Does queue locking on ONLY druid and version (as first and second parameters)
  def self.lock(*args)
    "lock:#{name}-#{args.slice(0..1)}"
  end

  # @param [String] druid
  # @param [Integer] version
  # @param [String] moab_replication_path The path containing the druid tree from which the zipped version should be
  #   created.  used via job.arguments in before_perform setup.
  def perform(druid, version, moab_replication_path) # rubocop:disable Lint/UnusedMethodArgument
    if File.exist?(file_path)
      FileUtils.touch(file_path)
    else
      create_zip!
    end
    part_keys.each do |part_key|
      PlexerJob.perform_later(druid, version, part_key, DruidVersionZipPart.new(zip, part_key).metadata)
    end
  end
end
