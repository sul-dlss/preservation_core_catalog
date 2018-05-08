module PreservationCatalog
  class S3
    class << self
      delegate :client, to: :bucket
    end

    # @return [Aws::S3::Bucket]
    def self.bucket
      resource.bucket(bucket_name)
    end

    # Because AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_REGION will be managed via
    # ENV vars, and the bucket must match those, we check for AWS_BUCKET_NAME first.
    # @return [String]
    def self.bucket_name
      ENV['AWS_BUCKET_NAME'] || Settings.aws.bucket_name
    end

    # @return [Aws::S3::Resource]
    def self.resource
      Aws::S3::Resource.new
    end
  end
end
