# Preconditions:
# PlexerJob has made a matching ZipPart row
#
# Responsibilities:
# Update DB per event info.
# Is this event the last needed for the DV to be complete?
# If NO, do nothing further.
# If YES, send a message to a non-job pub/sub queue.
class ResultsRecorderJob < ApplicationJob
  queue_as :endpoint_events
  attr_accessor :zmv, :zmvs

  before_perform do |job|
    job.zmvs ||= ZippedMoabVersion
                 .by_druid(job.arguments.first)
                 .joins(:archive_endpoint)
                 .where(version: job.arguments.second)
    job.zmv ||= zmvs.find_by!(archive_endpoints: { delivery_class: Object.const_get(job.arguments.fourth) })
  end

  # @param [String] druid
  # @param [Integer] version
  # @param [String] s3_part_key
  # @param [String] delivery_class Name of the worker class that performed delivery
  def perform(druid, version, s3_part_key, _delivery_class)
    part = zmv_part!(s3_part_key)
    part.ok!
    zmv.ok! if part.all_parts_replicated? # are all of the parts replicated for this endpoint?
    # only publish result if all of the parts replicated for all endpoints
    return unless zmvs.reload.all?(&:ok?)
    publish_result(message(druid, version).to_json)
  end

  private

  def zmv_part!(s3_part_key)
    raise "Status shifted underneath replication: #{zmv.inspect}" unless zmv.unreplicated?
    zmv.zip_parts.find_by!(
      suffix: File.extname(s3_part_key),
      status: 'unreplicated'
    )
  end

  # @return [Hash] response message to enqueue
  def message(druid, version)
    {
      druid: druid,
      version: version,
      endpoints: zmvs.pluck(:endpoint_name)
    }
  end

  # Currently using the Resque's underlying Redis instance, but we likely would
  # want something more durable like RabbitMQ for production.
  # @param [String] message JSON
  def publish_result(message)
    # Example: RabbitMQ using `connection` from the gem "Bunny":
    # connection.create_channel.fanout('replication.results').publish(message)
    Resque.redis.redis.lpush('replication.results', message)
  end
end
