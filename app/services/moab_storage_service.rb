# frozen_string_literal: true

# Responsibility: interactions with Moab storage to support read-only access for ReST API calls
class MoabStorageService
  # @return an XML file representing [Moab::FileInventoryDifference]
  #   from comparison of passed contentMetadata.xml with latest (or specified) version in Moab,
  #   for all files (default) or a specified subset (shelve|preserve|publish)
  # @raise ArgumentError or Moab::MoabRuntimeError as appropriate
  # @param [String] druid
  # @param [String] contentMetadata.xml to be compared against a version already in the Moab
  # @param [String] subset (default: 'all') which subset of files to compare (all|shelve|preserve|publish)
  # @param [Integer, nil] version of Moab to be compared against (defaults to latest version)
  def self.content_diff(druid, content_md, subset = 'all', version = nil)
    raise(ArgumentError, "No contentMetadata provided to MoabStorageService.content_diff for druid #{druid}") if content_md.blank?
    err_msg = "subset arg must be 'all', 'shelve', 'preserve', or 'publish' (MoabStorageService.content_diff for druid #{druid})"
    raise(ArgumentError, err_msg) unless ['all', 'shelve', 'preserve', 'publish'].include?(subset)
    Stanford::StorageServices.compare_cm_to_version(content_md, druid, subset, version)
  end

  # @return [Pathname] Pathname object containing the full path for the specified file
  # @raise ArgumentError or Moab::MoabRuntimeError as appropriate
  # @param [String] druid
  # @param [String] category category of desired file ('content', 'metadata', or 'manifest')
  # @param [String] filename name of the file (path relative to base directory)
  # @param [Integer, nil] version of the file (nil = latest)
  def self.filepath(druid, category, filename, version = nil)
    raise(ArgumentError, "No filename provided to MoabStorageService.filepath for druid #{druid}") if filename.blank?
    err_msg = "category arg must be 'content', 'metadata', or 'manifest' (MoabStorageService.filepath for druid #{druid})"
    raise(ArgumentError, err_msg) unless ['content', 'metadata', 'manifest'].include?(category)

    # DSA's SdrIngestService.transfer hits a pres cat endpoint that ultimately calls this method to get signatureCatalog (via pres client).  needs to
    # get primary.
    # relevant links:
    #  https://github.com/sul-dlss/preservation_robots/pull/244/files#diff-d6e54954863f787ff05c8112b773735dR49
    #  https://github.com/sul-dlss/dor-services-app/blob/7e94da22e7fa9e09af6fe88bd76085d7471f3548/app/services/sdr_ingest_service.rb#L13
    #  https://github.com/sul-dlss/preservation-client/blob/ed07535fc8c0c4c9e325a48de792d85bd6d1779c/lib/preservation/client/objects.rb#L86
    #  https://github.com/sul-dlss/moab-versioning/blob/9e24a35624b0c54c94a0386e1de7cbf52cf5b0d3/lib/moab/storage_repository.rb#L149
    #  https://github.com/sul-dlss/moab-versioning/blob/9e24a35624b0c54c94a0386e1de7cbf52cf5b0d3/lib/moab/storage_services.rb#L111
    # previously for this we called the Stanford::StorageServices.retrieve_file(category, filename, druid, version)
    # convenience method, but it doesn't account for the possibility of multiple moabs.  so we'll get the specific moab
    # we want from the primary moab location, and we'll do the rest of what Stanford::StorageServices.retrieve_file does to return a path
    primary_moab_location = CompleteMoab.primary_moab_location(druid)
    primary_storage_object = Stanford::StorageServices.search_storage_objects(druid).find do |moab|
      moab.object_pathname.to_s.start_with?(primary_moab_location)
    end
    primary_storage_object.find_object_version(version).find_filepath(category, filename)
  end

  def self.retrieve_content_file_group(druid)
    Moab::StorageServices.retrieve_file_group('content', druid)
  end
end
