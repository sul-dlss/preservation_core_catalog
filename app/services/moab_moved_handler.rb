# frozen_string_literal: true

##
# Service for handling a Moab that has moved
class MoabMovedHandler
  attr_reader :complete_moab, :results

  def initialize(complete_moab, results)
    @complete_moab = complete_moab
    @results = results
  end

  def check_and_handle_moved_moab
    update_moab_storage_root if moved_moab.exist?
  end

  private

  def moved_moab
    @moved_moab ||= Moab::StorageServices.find_storage_object(complete_moab.preserved_object.druid)
  end

  def validation_errors?
    object_validator = Stanford::StorageObjectValidator.new(moved_moab)
    object_validator.validation_errors(Settings.moab.allow_content_subdirs).any?
  end

  def storage_root
    @storage_root ||= MoabStorageRoot.find_by!(storage_location: File.join(moved_moab.storage_root.to_path, Settings.moab.storage_trunk))
  end

  def update_status_unknown
    complete_moab.status = 'validity_unknown'
    return unless complete_moab.status_changed?

    results.add_result(
      AuditResults::CM_STATUS_CHANGED, old_status: complete_moab.status_was, new_status: complete_moab.status
    )
  end

  def update_storage_root
    old_storage_root = complete_moab.moab_storage_root
    complete_moab.moab_storage_root = storage_root
    results.add_result(
      AuditResults::CM_STORAGE_ROOT_CHANGED, old_storage_root: old_storage_root.storage_location,
                                             new_storage_root: complete_moab.moab_storage_root.storage_location
    )
  end

  def update_moab_storage_root
    version = nil
    ActiveRecordUtils.with_transaction_and_rescue(results) do
      version = complete_moab.version
    end
    # Ensures Moab at the current location matches the catalog in all ways (e.g. version, full validation) except for disk location
    return if moved_moab.current_version_id != version
    return if validation_errors?

    # Update the disk location in the catalog
    transaction_ok = ActiveRecordUtils.with_transaction_and_rescue(results) do
      update_storage_root
      # Setting status to unknown triggers an async checksum validation.
      update_status_unknown
      complete_moab.save!
    end
    results.remove_db_updated_results unless transaction_ok
  end
end
