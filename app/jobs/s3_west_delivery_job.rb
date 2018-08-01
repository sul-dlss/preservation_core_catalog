# Posts zips to S3, if needed.
# Notify ResultsRecorderJob, if posted.
# @see PreservationCatalog::S3 for how S3 credentials and bucket are configured
class S3WestDeliveryJob < ZipPartJobBase
  queue_as :s3_us_west_2_delivery
  delegate :bucket, to: PreservationCatalog::S3
  # note: base class gives us `zip`, `dvz_part`

  before_enqueue { |job| job.zip_info_check!(job.arguments.fourth) }

  # @param [String] druid
  # @param [Integer] version
  # @param [String] part_s3_key
  # @param [Hash<Symbol => String, Integer>] metadata Zip info
  # @see PlexerJob#perform warning about why metadata must be passed
  def perform(druid, version, part_s3_key, metadata)
    s3_part = bucket.object(part_s3_key) # Aws::S3::Object
    return if s3_part.exists?
    s3_part.upload_file(
      dvz_part.file_path,
      metadata: stringify_values(metadata)
    )
    ResultsRecorderJob.perform_later(druid, version, part_s3_key, self.class.to_s)
  end

  # coerce size int to string (all values must be strings)
  # @param [Hash<Symbol => #to_s>] metadata
  # @return [Hash<Symbol => String>] metadata
  def stringify_values(metadata)
    metadata.merge(size: metadata[:size].to_s, parts_count: metadata[:parts_count].to_s)
  end
end
