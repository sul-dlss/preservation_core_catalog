# frozen_string_literal: true

# AuditResults allows the correct granularity of information to be reported in various contexts.
#   By collecting all the result information in this class, we keep the audit check code cleaner, and
#   enable an easy way to provide:
#    - the correct HTTP response code for ReST calls routed via controller
#    - error information reported to workflows
#    - information to Rails log
#    - in the future, this may also include reporting to the provenance database as well
#
# All results are kept in the result_array attribute, which is returned by the report_results method.
#   result_array = [result1, result2]
#   result1 = {response_code => msg}
#   result2 = {response_code => msg}
class AuditResults

  INVALID_ARGUMENTS = :invalid_arguments
  VERSION_MATCHES = :version_matches
  ACTUAL_VERS_GT_DB_OBJ = :actual_vers_gt_db_obj
  ACTUAL_VERS_LT_DB_OBJ = :actual_vers_lt_db_obj
  CREATED_NEW_OBJECT = :created_new_object
  DB_UPDATE_FAILED = :db_update_failed
  DB_OBJ_ALREADY_EXISTS = :db_obj_already_exists
  DB_OBJ_DOES_NOT_EXIST = :db_obj_does_not_exist
  CM_STATUS_CHANGED = :cm_status_changed
  CM_STORAGE_ROOT_CHANGED = :cm_storage_root_changed
  UNEXPECTED_VERSION = :unexpected_version
  INVALID_MOAB = :invalid_moab
  CM_PO_VERSION_MISMATCH = :cm_po_version_mismatch
  MOAB_NOT_FOUND = :moab_not_found
  MOAB_FILE_CHECKSUM_MISMATCH = :moab_file_checksum_mismatch
  MOAB_CHECKSUM_VALID = :moab_checksum_valid
  FILE_NOT_IN_MOAB = :file_not_in_moab
  FILE_NOT_IN_MANIFEST = :file_not_in_manifest
  FILE_NOT_IN_SIGNATURE_CATALOG = :file_not_in_signature_catalog
  MANIFEST_NOT_IN_MOAB = :manifest_not_in_moab
  SIGNATURE_CATALOG_NOT_IN_MOAB = :signature_catalog_not_in_moab
  INVALID_MANIFEST = :invalid_manifest
  UNABLE_TO_CHECK_STATUS = :unable_to_check_status
  ZIP_PART_NOT_FOUND = :zip_part_not_found
  ZIP_PART_CHECKSUM_MISMATCH = :zip_part_checksum_mismatch
  ZIP_PARTS_NOT_CREATED = :zip_parts_not_created
  ZIP_PARTS_COUNT_INCONSISTENCY = :zip_parts_count_inconsistency
  ZIP_PARTS_COUNT_DIFFERS_FROM_ACTUAL = :zip_parts_count_differs_from_actual
  ZIP_PARTS_NOT_ALL_REPLICATED = :zip_parts_not_all_replicated

  RESPONSE_CODE_TO_MESSAGES = {
    INVALID_ARGUMENTS => "encountered validation error(s): %{addl}",
    VERSION_MATCHES => "actual version (%{actual_version}) matches %{addl} db version",
    ACTUAL_VERS_GT_DB_OBJ => "actual version (%{actual_version}) greater than %{db_obj_name} db version (%{db_obj_version})",
    ACTUAL_VERS_LT_DB_OBJ => "actual version (%{actual_version}) less than %{db_obj_name} db version (%{db_obj_version}); ERROR!",
    CREATED_NEW_OBJECT => "added object to db as it did not exist",
    DB_UPDATE_FAILED => "db update failed: %{addl}",
    DB_OBJ_ALREADY_EXISTS => "%{addl} db object already exists",
    DB_OBJ_DOES_NOT_EXIST => "%{addl} db object does not exist",
    CM_STATUS_CHANGED => "CompleteMoab status changed from %{old_status} to %{new_status}",
    CM_STORAGE_ROOT_CHANGED => "CompleteMoab storage root changed from %{old_storage_root} to %{new_storage_root}",
    UNEXPECTED_VERSION => "actual version (%{actual_version}) has unexpected relationship to %{db_obj_name} db version (%{db_obj_version}); ERROR!",
    INVALID_MOAB => "Invalid Moab, validation errors: %{addl}",
    CM_PO_VERSION_MISMATCH => "CompleteMoab online Moab version %{cm_version} does not match PreservedObject current_version %{po_version}",
    MOAB_NOT_FOUND => "db CompleteMoab (created %{db_created_at}; last updated %{db_updated_at}) exists but Moab not found",
    MOAB_FILE_CHECKSUM_MISMATCH => "checksums for %{file_path} version %{version} do not match.",
    MOAB_CHECKSUM_VALID => "checksum(s) match",
    FILE_NOT_IN_MOAB => "%{manifest_file_path} refers to file (%{file_path}) not found in Moab",
    FILE_NOT_IN_MANIFEST => "Moab file %{file_path} was not found in Moab manifest %{manifest_file_path}",
    FILE_NOT_IN_SIGNATURE_CATALOG => "Moab file %{file_path} was not found in Moab signature catalog %{signature_catalog_path}",
    MANIFEST_NOT_IN_MOAB => "%{manifest_file_path} not found in Moab",
    SIGNATURE_CATALOG_NOT_IN_MOAB => "%{signature_catalog_path} not found in Moab",
    INVALID_MANIFEST => "unable to parse %{manifest_file_path} in Moab",
    UNABLE_TO_CHECK_STATUS => "unable to validate when CompleteMoab status is %{current_status}",
    ZIP_PART_NOT_FOUND => "replicated part not found on %{endpoint_name}: %{s3_key} was not found on %{bucket_name}",
    ZIP_PART_CHECKSUM_MISMATCH => "replicated md5 mismatch on %{endpoint_name}: %{s3_key} catalog md5 (%{md5}) doesn't match the replicated md5 (%{replicated_checksum}) on %{bucket_name}",
    ZIP_PARTS_NOT_CREATED => "%{version} on %{endpoint_name}: no zip_parts exist yet for this ZippedMoabVersion",
    ZIP_PARTS_COUNT_INCONSISTENCY => "%{version} on %{endpoint_name}: ZippedMoabVersion has variation in child parts_counts: %{child_parts_counts}",
    ZIP_PARTS_COUNT_DIFFERS_FROM_ACTUAL => "%{version} on %{endpoint_name}: ZippedMoabVersion stated parts count (%{db_count}) doesn't match actual number of zip parts rows (%{actual_count})",
    ZIP_PARTS_NOT_ALL_REPLICATED => "%{version} on %{endpoint_name}: not all ZippedMoabVersion parts are replicated yet: %{unreplicated_parts_list}"
  }.freeze

  WORKFLOW_REPORT_CODES = [
    ACTUAL_VERS_LT_DB_OBJ,
    DB_UPDATE_FAILED,
    DB_OBJ_ALREADY_EXISTS,
    UNEXPECTED_VERSION,
    CM_PO_VERSION_MISMATCH,
    MOAB_NOT_FOUND,
    MOAB_FILE_CHECKSUM_MISMATCH,
    FILE_NOT_IN_MOAB,
    FILE_NOT_IN_MANIFEST,
    FILE_NOT_IN_SIGNATURE_CATALOG,
    MANIFEST_NOT_IN_MOAB,
    SIGNATURE_CATALOG_NOT_IN_MOAB,
    INVALID_MANIFEST,
    UNABLE_TO_CHECK_STATUS
    # Temporary fix for workflow-service throwing exceptions
    # because some error reports from MoabReplicationAudit are too long
    # ZIP_PART_NOT_FOUND,
    # ZIP_PART_CHECKSUM_MISMATCH,
    # ZIP_PARTS_COUNT_INCONSISTENCY,
    # ZIP_PARTS_COUNT_DIFFERS_FROM_ACTUAL,
    # ZIP_PARTS_NOT_ALL_REPLICATED
  ].freeze

  HONEYBADGER_REPORT_CODES = [
    CM_STORAGE_ROOT_CHANGED,
    MOAB_FILE_CHECKSUM_MISMATCH,
    ZIP_PART_NOT_FOUND,
    ZIP_PART_CHECKSUM_MISMATCH,
    ZIP_PARTS_COUNT_INCONSISTENCY,
    ZIP_PARTS_COUNT_DIFFERS_FROM_ACTUAL,
    ZIP_PARTS_NOT_ALL_REPLICATED
  ].freeze

  DB_UPDATED_CODES = [
    CREATED_NEW_OBJECT,
    CM_STATUS_CHANGED,
    CM_STORAGE_ROOT_CHANGED
  ].freeze

  def self.logger_severity_level(result_code)
    case result_code
    when DB_OBJ_DOES_NOT_EXIST, ZIP_PARTS_NOT_CREATED, ZIP_PARTS_NOT_ALL_REPLICATED
      Logger::WARN
    when VERSION_MATCHES, ACTUAL_VERS_GT_DB_OBJ, CREATED_NEW_OBJECT, CM_STATUS_CHANGED, CM_STORAGE_ROOT_CHANGED, MOAB_CHECKSUM_VALID
      Logger::INFO
    else
      Logger::ERROR
    end
  end

  attr_reader :result_array, :druid, :moab_storage_root
  attr_accessor :actual_version, :check_name

  def initialize(druid, actual_version, moab_storage_root, check_name=nil)
    @druid = druid
    @actual_version = actual_version
    @moab_storage_root = moab_storage_root
    @check_name = check_name
    @result_array = []
  end

  def add_result(code, msg_args=nil)
    result_array << result_hash(code, msg_args)
  end

  # used when updates wrapped in transaction fail, and there is a need to ensure there is no db updated result
  def remove_db_updated_results
    result_array.delete_if { |res_hash| DB_UPDATED_CODES.include?(res_hash.keys.first) }
  end

  # output results to Rails.logger and send errors to WorkflowReporter
  # @return Array<Hash>
  #   results = [result1, result2]
  #   result1 = {response_code => msg}
  #   result2 = {response_code => msg}
  def report_results(logger=Rails.logger)
    candidate_workflow_results = []
    result_array.each do |r|
      log_result(r, logger)
      if r.key?(INVALID_MOAB)
        msg = "#{workflows_msg_prefix} || #{r.values.first}"
        WorkflowReporter.report_error(druid, actual_version, 'moab-valid', msg)
      elsif status_changed_to_ok?(r)
        WorkflowReporter.report_completed(druid, actual_version, 'preservation-audit')
      elsif WORKFLOW_REPORT_CODES.include?(r.keys.first)
        candidate_workflow_results << r
      end
      send_honeybadger_notification(r) if HONEYBADGER_REPORT_CODES.include?(r.keys.first)
    end
    report_errors_to_workflows(candidate_workflow_results)
    result_array
  end

  def contains_result_code?(code)
    result_array.detect { |result_hash| result_hash.key?(code) } != nil
  end

  def status_changed_to_ok?(result)
    /to ok$/.match(result[AuditResults::CM_STATUS_CHANGED]) != nil
  end

  def to_json(*_args)
    { druid: druid, result_array: result_array }.to_json
  end

  private

  def result_hash(code, msg_args=nil)
    { code => result_code_msg(code, msg_args) }
  end

  def report_errors_to_workflows(candidate_workflow_results)
    return if candidate_workflow_results.empty?
    msg = "#{workflows_msg_prefix} #{candidate_workflow_results.map(&:values).flatten.join(' && ')}"
    WorkflowReporter.report_error(druid, actual_version, 'preservation-audit', msg)
  end

  def log_result(result, logger)
    severity = self.class.logger_severity_level(result.keys.first)
    logger.add(severity, "#{log_msg_prefix} #{result.values.first}")
  end

  def send_honeybadger_notification(result)
    Honeybadger.notify("#{log_msg_prefix} #{result.values.first}")
  end

  def result_code_msg(code, addl=nil)
    arg_hash = { actual_version: actual_version }
    if addl.is_a?(Hash)
      arg_hash.merge!(addl)
    else
      arg_hash[:addl] = addl
    end
    RESPONSE_CODE_TO_MESSAGES[code] % arg_hash
  end

  def log_msg_prefix
    @log_msg_prefix ||= "#{check_name}(#{druid}, #{moab_storage_root&.name})"
  end

  def workflows_msg_prefix
    @workflows_msg_prefix ||= begin
      location_info = "actual location: #{moab_storage_root.name}" if moab_storage_root
      actual_version_info = "actual version: #{actual_version}" if actual_version
      "#{check_name} (#{location_info}; #{actual_version_info})"
    end
  end
end
