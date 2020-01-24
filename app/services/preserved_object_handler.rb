# frozen_string_literal: true

# creating a PreservedObject and/or updating check timestamps may require interactions
#  beyond the single PreservedObject model (e.g. CompleteMoab, PreservationPolicy).
#  This service class encapsulates logic to keep the controller and the model object
#    code simpler/thinner.
# NOTE: performing validation here to allow this class to be called directly avoiding http overhead
#
# inspired by http://www.thegreatcodeadventure.com/smarter-rails-services-with-active-record-modules/
class PreservedObjectHandler
  include ::MoabValidationHandler
  include ActiveModel::Validations

  validates :druid, presence: true, format: { with: DruidTools::Druid.pattern }
  validates :incoming_version, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :incoming_size, numericality: { only_integer: true, greater_than: 0 }
  validates_each :moab_storage_root do |record, attr, value|
    record.errors.add(attr, 'must be an actual MoabStorageRoot') unless value.is_a?(MoabStorageRoot)
  end

  attr_reader :druid, :incoming_version, :incoming_size, :moab_storage_root, :results
  attr_writer :logger

  delegate :storage_location, to: :moab_storage_root

  def initialize(druid, incoming_version, incoming_size, moab_storage_root)
    @druid = druid
    @incoming_version = version_string_to_int(incoming_version)
    @incoming_size = string_to_int(incoming_size)
    @moab_storage_root = moab_storage_root
    @results = AuditResults.new(druid, incoming_version, moab_storage_root)
    @logger = PreservationCatalog::Application.logger
  end

  # checksums_validated may be set to true if the caller takes responsibility for having validated the checksums
  def create_after_validation(checksums_validated = false)
    results.check_name = 'create_after_validation'
    if invalid?
      results.add_result(AuditResults::INVALID_ARGUMENTS, errors.full_messages)
    elsif PreservedObject.exists?(druid: druid)
      results.add_result(AuditResults::DB_OBJ_ALREADY_EXISTS, 'PreservedObject')
    elsif moab_validation_errors.empty?
      creation_status = (checksums_validated ? 'ok' : 'validity_unknown')
      create_db_objects(creation_status, checksums_validated)
    else
      create_db_objects('invalid_moab', checksums_validated)
    end

    results.report_results
  end

  # checksums_validated may be set to true if the caller takes responsibility for having validated the checksums
  def create(checksums_validated = false)
    results.check_name = 'create'
    if invalid?
      results.add_result(AuditResults::INVALID_ARGUMENTS, errors.full_messages)
    elsif PreservedObject.exists?(druid: druid)
      results.add_result(AuditResults::DB_OBJ_ALREADY_EXISTS, 'PreservedObject')
    else
      creation_status = (checksums_validated ? 'ok' : 'validity_unknown')
      ran_moab_validation! if checksums_validated # ensure validation timestamps updated
      create_db_objects(creation_status, checksums_validated)
    end

    results.report_results
  end

  # this is a long, complex method (shameless green); if it is refactored, revisit the exceptions in rubocop.yml
  def check_existence
    results.check_name = 'check_existence'

    if invalid?
      results.add_result(AuditResults::INVALID_ARGUMENTS, errors.full_messages)
      return results.report_results
    end

    return results.report_results unless check_preserved_object_db_obj_exists && check_moab_db_obj_exists

    unless online_moab_found?
      handle_missing_moab

      # Check if it moved to another location
      MoabMovedHandler.new(comp_moab, results).check_and_handle_moved_moab
      return results.report_results
    end

    Rails.logger.debug "check_existence #{druid} called"

    transaction_ok = with_active_record_transaction_and_rescue do
      raise_rollback_if_cm_po_version_mismatch

      return results.report_results unless can_validate_current_comp_moab_status?

      if incoming_version == comp_moab.version
        # Error thrown if comp_moab not found for this storage root and caught by with_active_record_transaction_and_rescue
        set_status_as_seen_on_disk(true) unless comp_moab.status == 'ok'
        results.add_result(AuditResults::VERSION_MATCHES, 'CompleteMoab')
      elsif incoming_version > comp_moab.version
        set_status_as_seen_on_disk(true) unless comp_moab.status == 'ok'
        results.add_result(AuditResults::ACTUAL_VERS_GT_DB_OBJ, db_obj_name: 'CompleteMoab', db_obj_version: comp_moab.version)
        if moab_validation_errors.empty?
          comp_moab.upd_audstamps_version_size(ran_moab_validation?, incoming_version, incoming_size)
          pres_object.current_version = incoming_version
          pres_object.save!
        else
          update_status('invalid_moab')
        end
      else # incoming_version < comp_moab.version
        set_status_as_seen_on_disk(false)
        results.add_result(AuditResults::ACTUAL_VERS_LT_DB_OBJ, db_obj_name: 'CompleteMoab', db_obj_version: comp_moab.version)
      end
      comp_moab.update_audit_timestamps(ran_moab_validation?, true)
      comp_moab.save!
    end
    results.remove_db_updated_results unless transaction_ok
    results.report_results
  end

  def check_preserved_object_db_obj_exists
    with_active_record_transaction_and_rescue do
      # If it doesn't exist, error will be caught and DB_OBJ_DOES_NOT_EXIST added to results
      pres_object
      return true
    end
    if moab_validation_errors.empty?
      create_db_objects('validity_unknown')
    else
      create_db_objects('invalid_moab')
    end
    false
  end

  def check_moab_db_obj_exists
    with_active_record_transaction_and_rescue do
      # If it doesn't exist, error will be caught and DB_OBJ_DOES_NOT_EXIST added to results
      comp_moab
      return true
    end
    false
  end

  def confirm_version
    results.check_name = 'confirm_version'
    if invalid?
      results.add_result(AuditResults::INVALID_ARGUMENTS, errors.full_messages)
    else
      Rails.logger.debug "confirm_version #{druid} called"
      # NOTE: we deal with active record transactions in confirm_online_version, not here
      confirm_online_version
    end

    results.report_results
  end

  # checksums_validated may be set to true if the caller takes responsibility for having validated the checksums
  def update_version_after_validation(checksums_validated = false)
    results.check_name = 'update_version_after_validation'
    if invalid?
      results.add_result(AuditResults::INVALID_ARGUMENTS, errors.full_messages)
    elsif PreservedObject.exists?(druid: druid)
      Rails.logger.debug "update_version_after_validation #{druid} called"
      if moab_validation_errors.empty?
        # NOTE: we deal with active record transactions in update_online_version, not here
        new_status = (checksums_validated ? 'ok' : 'validity_unknown')
        update_online_version(new_status, false, checksums_validated)
      else
        Rails.logger.debug "update_version_after_validation #{druid} found validation errors"
        if checksums_validated
          update_online_version('invalid_moab', false, true)
          # for case when no db updates b/c pres_obj version != comp_moab version
          update_cm_invalid_moab unless comp_moab.invalid_moab?
        else
          update_online_version('validity_unknown', false, false)
          # for case when no db updates b/c pres_obj version != comp_moab version
          update_cm_validity_unknown unless comp_moab.validity_unknown?
        end
      end
    else
      results.add_result(AuditResults::DB_OBJ_DOES_NOT_EXIST, 'PreservedObject')
      if moab_validation_errors.empty?
        create_db_objects('validity_unknown')
      else
        create_db_objects('invalid_moab')
      end
    end

    results.report_results
  end

  # checksums_validated may be set to true if the caller takes responsibility for having validated the checksums
  def update_version(checksums_validated = false)
    results.check_name = 'update_version'
    if invalid?
      results.add_result(AuditResults::INVALID_ARGUMENTS, errors.full_messages)
    else
      Rails.logger.debug "update_version #{druid} called"
      # only change status if checksums_validated is false
      new_status = (checksums_validated ? nil : 'validity_unknown')
      # NOTE: we deal with active record transactions in update_online_version, not here
      update_online_version(new_status, true, checksums_validated)
    end

    results.report_results
  end

  def pres_object
    @pres_object ||= PreservedObject.find_by!(druid: druid)
  end

  def comp_moab
    # FIXME: what if there is more than one associated comp_moab?
    @comp_moab ||= pres_object.complete_moabs.find_by!(moab_storage_root: moab_storage_root)
  end

  alias complete_moab comp_moab

  private

  def create_db_objects(status, checksums_validated = false)
    cm_attrs = {
      version: incoming_version,
      size: incoming_size,
      moab_storage_root: moab_storage_root,
      status: status
    }
    t = Time.current
    if ran_moab_validation?
      cm_attrs[:last_version_audit] = t
      cm_attrs[:last_moab_validation] = t
    end
    cm_attrs[:last_checksum_validation] = t if checksums_validated
    ppid = PreservationPolicy.default_policy.id

    # TODO: remove tests' dependence on 2 "create!" calls, use single built-in AR transactionality
    transaction_ok = with_active_record_transaction_and_rescue do
      PreservedObject
        .create!(druid: druid, current_version: incoming_version, preservation_policy_id: ppid)
        .complete_moabs.create!(cm_attrs)
    end
    results.add_result(AuditResults::CREATED_NEW_OBJECT) if transaction_ok
  end

  # TODO: this is "too complex" per rubocop: shameless green implementation
  # NOTE: if we can reduce complexity, remove Metrics/PerceivedComplexity exception in .rubocop.yml
  def update_online_version(status=nil, set_status_to_unexp_version=false, checksums_validated=false)
    transaction_ok = with_active_record_transaction_and_rescue do
      raise_rollback_if_cm_po_version_mismatch

      # FIXME: what if there is more than one associated comp_moab?
      if incoming_version > comp_moab.version && comp_moab.matches_po_current_version?
        # add results without db updates
        code = AuditResults::ACTUAL_VERS_GT_DB_OBJ
        results.add_result(code, db_obj_name: 'CompleteMoab', db_obj_version: comp_moab.version)

        comp_moab.upd_audstamps_version_size(ran_moab_validation?, incoming_version, incoming_size)
        comp_moab.last_checksum_validation = Time.current if checksums_validated && comp_moab.last_checksum_validation
        update_status(status) if status
        comp_moab.save!
        pres_object.current_version = incoming_version
        pres_object.save!
      else
        status = 'unexpected_version_on_storage' if set_status_to_unexp_version
        update_cm_unexpected_version(status)
      end
    end

    results.remove_db_updated_results unless transaction_ok
  end

  def raise_rollback_if_cm_po_version_mismatch
    unless comp_moab.matches_po_current_version?
      cm_version = comp_moab.version
      po_version = comp_moab.preserved_object.current_version
      res_code = AuditResults::CM_PO_VERSION_MISMATCH
      results.add_result(res_code, { cm_version: cm_version, po_version: po_version })
      raise ActiveRecord::Rollback, "CompleteMoab version #{cm_version} != PreservedObject current_version #{po_version}"
    end
  end

  def update_cm_invalid_moab
    transaction_ok = with_active_record_transaction_and_rescue do
      update_status('invalid_moab')
      comp_moab.update_audit_timestamps(ran_moab_validation?, false)
      comp_moab.save!
    end
    results.remove_db_updated_results unless transaction_ok
  end

  def update_cm_validity_unknown
    transaction_ok = with_active_record_transaction_and_rescue do
      update_status('validity_unknown')
      comp_moab.update_audit_timestamps(ran_moab_validation?, false)
      comp_moab.save!
    end
    results.remove_db_updated_results unless transaction_ok
  end

  def update_cm_unexpected_version(new_status)
    results.add_result(AuditResults::UNEXPECTED_VERSION, db_obj_name: 'CompleteMoab', db_obj_version: comp_moab.version)
    version_comparison_results

    update_status(new_status) if new_status
    comp_moab.update_audit_timestamps(ran_moab_validation?, true)
    comp_moab.save!
  end

  # shameless green implementation
  def confirm_online_version
    transaction_ok = with_active_record_transaction_and_rescue do
      raise_rollback_if_cm_po_version_mismatch

      return results.report_results unless can_validate_current_comp_moab_status?

      if incoming_version == comp_moab.version
        set_status_as_seen_on_disk(true) unless comp_moab.status == 'ok'
        results.add_result(AuditResults::VERSION_MATCHES, 'CompleteMoab')
      else
        set_status_as_seen_on_disk(false)
        results.add_result(AuditResults::UNEXPECTED_VERSION, db_obj_name: 'CompleteMoab', db_obj_version: comp_moab.version)
      end
      comp_moab.update_audit_timestamps(ran_moab_validation?, true)
      comp_moab.save!
    end
    results.remove_db_updated_results unless transaction_ok
  end

  # this wrapper reads a little nicer in this class, since POH is always doing this the same way
  def with_active_record_transaction_and_rescue
    ActiveRecordUtils.with_transaction_and_rescue(results) { yield }
  end

  # expects @incoming_version to be numeric
  def version_comparison_results
    if incoming_version == comp_moab.version
      results.add_result(AuditResults::VERSION_MATCHES, comp_moab.class.name)
    elsif incoming_version < comp_moab.version
      results.add_result(
        AuditResults::ACTUAL_VERS_LT_DB_OBJ,
        { db_obj_name: comp_moab.class.name, db_obj_version: comp_moab.version }
      )
    elsif incoming_version > comp_moab.version
      results.add_result(
        AuditResults::ACTUAL_VERS_GT_DB_OBJ,
        { db_obj_name: comp_moab.class.name, db_obj_version: comp_moab.version }
      )
    end
  end

  def version_string_to_int(val)
    result = string_to_int(val)
    return result if result.instance_of?(Integer)
    # accommodate 'vnnn' strings from Moab version directories
    return val[1..-1].to_i if val.instance_of?(String) && val.match(/^v\d+$/)
    val
  end

  def string_to_int(val)
    return if val.blank?
    return val if val.instance_of?(Integer) # NOTE: negative integers caught with validation
    return val.to_i if val.instance_of?(String) && val.scan(/\D/).empty?
    val
  end
end
