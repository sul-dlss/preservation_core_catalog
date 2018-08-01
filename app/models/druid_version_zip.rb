require 'open3'

# For replication purposes, we may have to chunk archival objects (zips) of Moab versions into multiple files to avoid
#   unwieldy file sizes.  This model is for interaction with the entire multi-part zip;
#   see DruidVersionZipPart for individual parts; note that all zips will have at least one part.
# See comment on part_paths method re: individual part suffixes.
# Just a regular model, not an ActiveRecord-backed model
class DruidVersionZip
  attr_reader :druid, :version
  delegate :base64digest, :hexdigest, to: :md5

  # @param [String] druid
  # @param [Integer] version
  def initialize(druid, version)
    @druid = DruidTools::Druid.new(druid.downcase)
    @version = version
  end

  # @return [String] Filename/key without extension, in common to all this object's zip parts
  def base_key
    @base_key ||= s3_key.sub(/.zip\z/, '')
  end

  # Creates a zip of Druid-Version content.
  # Changes directory so that the storage root (and druid tree) are not part of
  # the archival directory structure, just the object, e.g. starting at 'ab123cd4567/...' directory,
  # not 'ab/123/cd/4567/ab123cd4567/...'
  def create_zip!
    ensure_zip_directory!
    Dir.chdir(work_dir.to_s) do
      combined, status = Open3.capture2e(zip_command)
      raise "zipmaker failure #{combined}" unless status.success?
    end
  end

  # Ensure the directory the zip will live in exists
  # @return [Pathname] the existing or created directory
  def ensure_zip_directory!
    Pathname.new(file_path).tap { |pn| pn.dirname.mkpath }
  end

  # @param [Integer] count Number of parts
  # @return [Array<String>] Ordered pathnames expected to correspond to a zip broken into a given number of parts
  def expected_part_keys(count = 1)
    raise ArgumentError, "count (#{count}) must be >= 1" if count < 1
    [s3_key].concat(
      (1..(count - 1)).map { |n| base_key + format('.z%02d', n) }
    )
  end

  # @param [String] suffix, e.g. '.zip', '.z01', '.z125', etc., including the dot
  # @return [String] s3_key for the zip part specified by suffix
  # @see [S3 key name performance implications] https://docs.aws.amazon.com/AmazonS3/latest/dev/request-rate-perf-considerations.html
  # @example return 'ab/123/cd/4567/ab123cd4567.v0001.zip'
  def s3_key(suffix = '.zip')
    druid.tree.join('/') + ".#{v_version}#{suffix}"
  end

  # @return [String] Path to the local temporary transfer root (.zip) part
  def file_path
    File.join(zip_storage, s3_key)
  end

  # WITHOUT (re)digesting the file, convert a hexdigest MD5 value to base64-endcoded equivalent.
  # Motivation: we store hexdigest and S3 requires base64 in headers.
  # @param [String] hex
  # @return [String] base64 equivalent
  def hex_to_base64(hex)
    [[hex].pack("H*")].pack("m0")
  end

  def moab_version_path
    @moab_version_path ||= Moab::StorageServices.object_version_path(druid.id, version)
  end

  # @return [Array<String>] relative paths, i.e. s3_part_keys for existing parts
  def part_keys
    part_paths.map { |part| part.relative_path_from(zip_storage).to_s }
  end

  # note that if there is only ONE part, it will end .zip;  if there are multiple parts,
  #  the last one will end .zip, so two parts is:  .z01, zip. (this agrees with zip utility)
  # @return [Array<Pathname>] Existing pathnames for zip parts based on glob (.zip, .z01, .z02, etc.)
  def part_paths
    @part_paths ||= Pathname.glob(file_path.sub(/.zip\z/, '.z*'))
  end

  # @return [String] "v" with zero-padded 4-digit version, e.g., v0001
  def v_version
    format("v%04d", version)
  end

  # @return [Pathname] The proper directory in which to execute zip_command
  def work_dir
    Pathname.new(moab_version_path).parent.parent
  end

  # @return [String] shell command to unzip
  # def unzip_command
  #   "unzip #{file_path} -d #{place_to_unzip}"
  # end

  # Presumes execution just "above" the druid dir in the druid tree, i.e. if the Moab is:
  #   /storage_trunk_01/bj/102/hs/9687/bj102hs9687/v0003/...
  # This command should execute from:
  #   /storage_trunk_01/bj/102/hs/9687/
  # @see #work_dir
  # @return [String] shell command to create this zip
  def zip_command
    "zip -r0X -s #{zip_split_size} #{file_path} #{druid.id}/#{v_version}"
  end

  # We presume the system guts do not change underneath a given class instance.
  # We want to avoid shelling out (forking) unnecessarily, just for the version.
  def zip_version
    @@zip_version ||= fetch_zip_version # rubocop:disable Style/ClassVars
  end

  # @return [Pathname]
  def zip_storage
    @zip_storage ||= Pathname.new(Settings.zip_storage)
  end

  private

  # @return [String] e.g. 'Zip 3.0 (July 5th 2008)' or 'Zip 3.0.1'
  def fetch_zip_version
    match = nil
    IO.popen("zip -v") do |io|
      re = zip_version_regexp
      io.find { |line| match = line.match(re) }
    end
    return match[1] if match && match[1].present?
    raise 'No version info matched from `zip -v` ouptut'
  end

  # @return [String] the option included with "zip -s"
  def zip_split_size
    '10g'
  end

  def zip_version_regexp
    /This is (Zip \d+(\.\d)+\s*(\(.*\d{4}\))?)/
  end
end
