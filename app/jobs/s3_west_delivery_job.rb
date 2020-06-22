# frozen_string_literal: true

# Posts zips to S3, if needed.
# Notify ResultsRecorderJob, if posted.
# @see PreservationCatalog::Aws for how S3 credentials and bucket are configured
# @note This name is slightly misleading, as this class solely deals with AWS US West 2 endpoint
class S3WestDeliveryJob < ZipPartJobBase
  queue_as :s3_us_west_2_delivery
  # note: base class gives us `zip`, `dvz_part` (but not an instance of zip with the path to the moab used for creation)

  before_enqueue { |job| job.zip_info_check!(job.arguments.fourth) }

  # @param [String] druid
  # @param [Integer] version
  # @param [String] part_s3_key
  # @param [Hash<Symbol => String, Integer>] metadata Zip info
  # @see PlexerJob#perform warning about why metadata must be passed
  def perform(druid, version, part_s3_key, metadata)
    s3_part = bucket.object(part_s3_key) # ::Aws::S3::Object
    return if s3_part.exists?

    fresh_md5 = dvz_part.read_md5
    given_md5 = metadata[:checksum_md5]
    raise "#{part_s3_key} MD5 mismatch: passed #{given_md5}, computed #{fresh_md5}" unless fresh_md5 == given_md5

    s3_part.upload_file(dvz_part.file_path, metadata: stringify_values(metadata))
    ResultsRecorderJob.perform_later(druid, version, part_s3_key, self.class.to_s)
  end

  def bucket
    PreservationCatalog::AwsProvider.new(
      region: Settings.zip_endpoints.aws_s3_west_2.region,
      access_key_id: Settings.zip_endpoints.aws_s3_west_2.access_key_id,
      secret_access_key: Settings.zip_endpoints.aws_s3_west_2.secret_access_key
    ).bucket
  end

  # coerce size int to string (all values must be strings)
  # @param [Hash<Symbol => #to_s>] metadata
  # @return [Hash<Symbol => String>] metadata
  def stringify_values(metadata)
    metadata.merge(size: metadata[:size].to_s, parts_count: metadata[:parts_count].to_s)
  end
end
