# frozen_string_literal: true

# A service for auditing complete_moabs against moabs on disk (and vice versa.)
# If a preserved_object is missing, it is created.
# If a complete_moab is missing for a moab, it is created.
# For each complete_moab / moab, versions are compared and validations possibly performed.
# Complete_moabs are deleted for any moved moabs (i.e., moab missing for complete_moab, but another moab exists in a different location)
class PreservedObjectAuditService

  attr_reader :druid, :all_results
  attr_writer :logger

  def initialize(druid)
    @druid = druid
    @logger = PreservationCatalog::Application.logger
    # Each moab / complete moab has own audit result
    create_all_results
  end

  def audit
    unless preserved_object
      # TODO: Is raising the correct way to handle?
      raise "No preserved object and no moabs on disk for #{druid}" if moabs.empty?
      create_preserved_object
    end
    raise 'preserved_object does not exist' unless preserved_object # Assertion

    # For each moab, if there is no complete_moab then create one.
    create_missing_complete_moabs

    preserved_object.complete_moabs.all.each do |complete_moab|
      moab = moab_for_complete_moab(complete_moab)

      # Moab on disk does not exist
      unless moab.exist?
        handle_missing_moab(complete_moab)
        next
      end

      if moab.current_version_id == complete_moab.version
        handle_version_matches(complete_moab)
        if complete_moab.status == 'ok'
          complete_moab.update_audit_timestamps(false, true) # Version audited
          next
        end
      end

      next unless validate(moab, complete_moab) # Also adds to results and updates complete_moab

      if moab.current_version_id < complete_moab.version
        handle_unexpected_version(complete_moab)
        next
      end

      update_status(complete_moab,'validity_unknown') # This will queue a checksum validation.

      handle_bumped_version(complete_moab, moab) if moab.current_version_id > complete_moab.version

      handle_preserved_object_version_mismatch(complete_moab) if preserved_object.current_version != complete_moab.version

    end

    # Save all of the complete_moabs
    preserved_object.complete_moabs.all.each { |complete_moab| complete_moab.save! }

    delete_moved_complete_moabs

    # Report the results
    all_results.values.map { |results| results.report_results}
  end

  private

  def preserved_object
    @preserved_object ||= PreservedObject.find_by!(druid: druid)
  end

  def preservation_policy
    PreservationPolicy.default_policy.id
  end

  def storage_trunk
    Settings.moab.storage_trunk
  end

  def moabs
    @moabs ||= Moab::StorageServices.search_storage_objects(druid)
  end

  def create_preserved_object
    raise "preserved_object already exists" if preserved_object # Assertion
    # Setting current_version to 1 should be OK because will be corrected.
    @preserved_object = PreservedObject.create!(druid: druid, current_version: 1, preservation_policy_id: preservation_policy)
    # TODO: Should this be added to results? Since results are for a complete_moab, does that make sense?
    # results.add_result(AuditResults::CREATED_NEW_OBJECT)
  end

  def create_complete_moab(moab)
    raise "preserved_object does not exist" unless preserved_object # Assertion

    preserved_object.complete_moabs.create!(
        version: moab.current_version_id,
        size: moab.size,
        moab_storage_root: find_moab_storage_root(moab),
        status: 'validity_unknown'
    )
    results_for_moab(moab).add_result(AuditResults::CREATED_NEW_OBJECT)
  end

  def create_missing_complete_moabs
    moabs.each do |moab|
      moab_storage_root = find_moab_storage_root(moab)
      create_complete_moab(moab) unless preserved_object.complete_moabs.exists?(moab_storage_root: moab_storage_root)
    end
  end

  def create_all_results
    @all_results = {}
    moabs.each do |moab|
      moab_storage_root = find_moab_storage_root(moab)
      all_results[moab_storage_root] = AuditResults.new(druid, moab.current_version_id, moab_storage_root)
    end

    return unless preserved_object

    preserved_object.complete_moabs.all.each do |complete_moab|
      all_results[moab_storage_root] = AuditResults.new(druid, nil, complete_moab.moab_storage_root) unless all_results.has_key?(complete_moab.moab_storage_root)
    end
  end

  def update_status(complete_moab, new_status)
    complete_moab.status = new_status
    return unless complete_moab.status_changed?

    results_for_complete_moab(complete_moab).add_result(
        AuditResults::CM_STATUS_CHANGED, old_status: complete_moab.status_was, new_status: complete_moab.status
    )
  end

  def find_moab_storage_root(moab)
    storage_location = "#{moab.object_pathname.to_s.split(storage_trunk).first}#{storage_trunk}"
    MoabStorageRoot.find_by!(storage_location: storage_location)
  end

  def moab_for_complete_moab(complete_moab)
    object_dir = "#{complete_moab.moab_storage_root.storage_location}/#{DruidTools::Druid.new(druid).tree.join('/')}"
    Moab::StorageObject.new(druid, object_dir)
  end

  def results_for_complete_moab(complete_moab)
    all_results[complete_moab.moab_storage_root]
  end

  def results_for_moab(moab)
    all_results[find_moab_storage_root(moab)]
  end

  def validate(moab, complete_moab)
    object_validator = Stanford::StorageObjectValidator.new(moab)
    moab_errors = object_validator.validation_errors(Settings.moab.allow_content_subdirs)
    complete_moab.update_audit_timestamps(true, true) # Moab validated and version audited
    if moab_errors.any?
      moab_error_msgs = []
      moab_errors.each do |error_hash|
        moab_error_msgs += error_hash.values
      end
      results_for_moab(moab).add_result(AuditResults::INVALID_MOAB, moab_error_msgs)
      update_status(complete_moab, 'invalid_moab')
      return false
    end
    true
  end

  def delete_moved_complete_moabs
    # Must be at least one other complete_moab that != MOAB_NOT_FOUND
    return if preserved_object.complete_moabs.where.not(status: MOAB_NOT_FOUND).exists?

    preserved_object.complete_moabs.where(status: MOAB_NOT_FOUND).each do |complete_moab|
      results_for_complete_moab(complete_moab).add_result(AuditResults::DELETED_OBJECT)
      complete_moab.destroy
    end
  end

  def handle_missing_moab(complete_moab)
    update_status(complete_moab, 'online_moab_not_found')
    results_for_complete_moab(complete_moab).add_result(AuditResults::MOAB_NOT_FOUND,
                                                        db_created_at: complete_moab.created_at.iso8601,
                                                        db_updated_at: complete_moab.updated_at.iso8601)
  end

  def handle_unexpected_version(complete_moab)
    update_status(complete_moab, 'unexpected_version_on_storage')
    results_for_complete_moab(complete_moab).add_result(
      AuditResults::UNEXPECTED_VERSION, db_obj_name: 'CompleteMoab', db_obj_version: complete_moab.version
    )
  end

  def handle_bumped_version(complete_moab, moab)
    results_for_complete_moab(complete_moab).add_result(
        AuditResults::ACTUAL_VERS_GT_DB_OBJ, db_obj_name: 'CompleteMoab', db_obj_version: complete_moab.version
    )
    complete_moab.upd_audstamps_version_size(true, moab.current_version_id, moab.size)
    if preserved_object.current_version < moab.current_version_id
      preserved_object.current_version = moab.current_version_id
      preserved_object.save!
    end
  end

  def handle_version_matches(complete_moab)
    results_for_complete_moab(complete_moab).add_result(AuditResults::VERSION_MATCHES, 'CompleteMoab')
  end

  def handle_preserved_object_version_mismatch(complete_moab)
    results_for_complete_moab(complete_moab).add_result(
        AuditResults::CM_PO_VERSION_MISMATCH, cm_version: complete_moab.version, po_version: preserved_object.current_version
    )
  end
end