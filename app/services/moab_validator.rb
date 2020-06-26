# frozen_string_literal: true

##
# service class with methods for running StorageObjectValidator
class MoabValidator
  attr_reader :druid, :storage_location, :results, :caller_validates_checksums

  # @param druid [String] the druid for the moab being audited
  # @param storage_location [String] the root directory holding the druid tree (the storage root path)
  # @param results [AuditResults] the instance the including class is using to track findings of interest
  # @param complete_moab [CompleteMoab, nil] instance of the complete moab being validated, if already available from the caller.  if nil, will query
  #   as needed (and memoize result).
  # @caller_validates_checksums [Boolean] defaults to false.  was this called by code that re-computes checksums to confirm that they match the
  #   values listed in the manifests?
  def initialize(druid:, storage_location:, results:, complete_moab: nil, caller_validates_checksums: false)
    @druid = druid
    @storage_location = storage_location
    @results = results
    @complete_moab = complete_moab
    @caller_validates_checksums = caller_validates_checksums
  end

  def object_dir
    @object_dir ||= DruidTools::Druid.new(druid, storage_location).path
  end

  def complete_moab
    # There should be at most one CompleteMoab for a given druid on a given storage location:
    # * At the DB level, there's a unique index on druid for preserved_objects, a unique index on storage_location
    # for moab_storage_roots, and a unique index on the combo of preserved_object_id and moab_storage_root_id for
    # complete_moabs.
    # * A moab always lives in the druid tree path of the storage_location, so there is only one
    # possible moab path for any given druid in a given storage root.
    @complete_moab ||= CompleteMoab.joins(:preserved_object, :moab_storage_root).find_by!(
      preserved_objects: { druid: druid }, moab_storage_roots: { storage_location: storage_location }
    )
  end

  def moab
    @moab ||= Moab::StorageObject.new(druid, object_dir)
  end

  def can_validate_current_comp_moab_status?
    can_do = caller_validates_checksums || complete_moab.status != 'invalid_checksum'
    results.add_result(AuditResults::UNABLE_TO_CHECK_STATUS, current_status: complete_moab.status) unless can_do
    can_do
  end

  def moab_validation_errors
    @moab_validation_errors ||=
      begin
        object_validator = Stanford::StorageObjectValidator.new(moab)
        moab_errors = object_validator.validation_errors(Settings.moab.allow_content_subdirs)
        ran_moab_validation!
        if moab_errors.any?
          moab_error_msgs = []
          moab_errors.each do |error_hash|
            moab_error_msgs += error_hash.values
          end
          results.add_result(AuditResults::INVALID_MOAB, moab_error_msgs)
        end
        moab_errors
      end
  end

  def ran_moab_validation!
    @ran_moab_validation = true
  end

  def ran_moab_validation?
    @ran_moab_validation ||= false
  end

  def update_status(new_status)
    complete_moab.status = new_status

    if complete_moab.status_changed?
      results.add_result(
        AuditResults::CM_STATUS_CHANGED, old_status: complete_moab.status_was, new_status: complete_moab.status
      )
    end

    complete_moab.status_details = results.results_as_string
  end

  def mark_moab_not_found
    results.add_result(AuditResults::MOAB_NOT_FOUND,
                       db_created_at: complete_moab.created_at.iso8601,
                       db_updated_at: complete_moab.updated_at.iso8601)
    update_status('online_moab_not_found')
  end

  # found_expected_version is a boolean indicating whether the latest version of the moab
  # on disk is the expected version according to the catalog.  NOTE: in the case of an update
  # this might mean the on disk version is one higher than the catalog version, if the
  # catalog hasn't been updated yet.
  # @param [Boolean] found_expected_version
  # @return [void]
  def set_status_as_seen_on_disk(found_expected_version) # rubocop:disable Naming/AccessorMethodName
    begin
      return update_status('invalid_moab') if moab_validation_errors.any?
    rescue Errno::ENOENT
      return mark_moab_not_found
    end

    return update_status('unexpected_version_on_storage') unless found_expected_version

    # NOTE: subclasses which override this method should NOT perform checksum validation inside of this method!
    # CV is expensive, and can run a while, and this method should likely be called from within a DB transaction,
    # but CV definitely shouldn't happen inside a DB transaction.
    if results.contains_result_code?(AuditResults::MOAB_CHECKSUM_VALID)
      update_status('ok')
    elsif caller_validates_checksums
      update_status('invalid_checksum')
    else
      update_status('validity_unknown')
    end
  end
end
