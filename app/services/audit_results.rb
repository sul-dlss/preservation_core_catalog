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
  ACTUAL_VERS_GT_DB_OBJ = :actual_vers_gt_db_obj
  ACTUAL_VERS_LT_DB_OBJ = :actual_vers_lt_db_obj
  CM_PO_VERSION_MISMATCH = :cm_po_version_mismatch
  CM_STATUS_CHANGED = :cm_status_changed
  CREATED_NEW_OBJECT = :created_new_object
  DB_OBJ_ALREADY_EXISTS = :db_obj_already_exists
  DB_OBJ_DOES_NOT_EXIST = :db_obj_does_not_exist
  DB_UPDATE_FAILED = :db_update_failed
  FILE_NOT_IN_MANIFEST = :file_not_in_manifest
  FILE_NOT_IN_MOAB = :file_not_in_moab
  FILE_NOT_IN_SIGNATURE_CATALOG = :file_not_in_signature_catalog
  INVALID_ARGUMENTS = :invalid_arguments
  INVALID_MANIFEST = :invalid_manifest
  INVALID_MOAB = :invalid_moab
  MANIFEST_NOT_IN_MOAB = :manifest_not_in_moab
  MOAB_CHECKSUM_VALID = :moab_checksum_valid
  MOAB_FILE_CHECKSUM_MISMATCH = :moab_file_checksum_mismatch
  MOAB_NOT_FOUND = :moab_not_found
  SIGNATURE_CATALOG_NOT_IN_MOAB = :signature_catalog_not_in_moab
  UNABLE_TO_CHECK_STATUS = :unable_to_check_status
  UNEXPECTED_VERSION = :unexpected_version
  VERSION_MATCHES = :version_matches
  ZIP_PART_CHECKSUM_MISMATCH = :zip_part_checksum_mismatch
  ZIP_PART_NOT_FOUND = :zip_part_not_found
  ZIP_PARTS_COUNT_DIFFERS_FROM_ACTUAL = :zip_parts_count_differs_from_actual
  ZIP_PARTS_COUNT_INCONSISTENCY = :zip_parts_count_inconsistency
  ZIP_PARTS_NOT_ALL_REPLICATED = :zip_parts_not_all_replicated
  ZIP_PARTS_NOT_CREATED = :zip_parts_not_created

  RESPONSE_CODE_TO_MESSAGES = {
    ACTUAL_VERS_GT_DB_OBJ => "actual version (%{actual_version}) greater than %{db_obj_name} db version (%{db_obj_version})",
    ACTUAL_VERS_LT_DB_OBJ => "actual version (%{actual_version}) less than %{db_obj_name} db version (%{db_obj_version}); ERROR!",
    CM_PO_VERSION_MISMATCH => "CompleteMoab online Moab version %{cm_version} does not match PreservedObject current_version %{po_version}",
    CM_STATUS_CHANGED => "CompleteMoab status changed from %{old_status} to %{new_status}",
    CREATED_NEW_OBJECT => "added object to db as it did not exist",
    DB_OBJ_ALREADY_EXISTS => "%{addl} db object already exists",
    DB_OBJ_DOES_NOT_EXIST => "%{addl} db object does not exist",
    DB_UPDATE_FAILED => "db update failed: %{addl}",
    FILE_NOT_IN_MANIFEST => "Moab file %{file_path} was not found in Moab manifest %{manifest_file_path}",
    FILE_NOT_IN_MOAB => "%{manifest_file_path} refers to file (%{file_path}) not found in Moab",
    FILE_NOT_IN_SIGNATURE_CATALOG => "Moab file %{file_path} was not found in Moab signature catalog %{signature_catalog_path}",
    INVALID_ARGUMENTS => "encountered validation error(s): %{addl}",
    INVALID_MANIFEST => "unable to parse %{manifest_file_path} in Moab",
    INVALID_MOAB => "Invalid Moab, validation errors: %{addl}",
    MANIFEST_NOT_IN_MOAB => "%{manifest_file_path} not found in Moab",
    MOAB_CHECKSUM_VALID => "checksum(s) match",
    MOAB_FILE_CHECKSUM_MISMATCH => "checksums for %{file_path} version %{version} do not match.",
    MOAB_NOT_FOUND => "db CompleteMoab (created %{db_created_at}; last updated %{db_updated_at}) exists but Moab not found",
    SIGNATURE_CATALOG_NOT_IN_MOAB => "%{signature_catalog_path} not found in Moab",
    UNABLE_TO_CHECK_STATUS => "unable to validate when CompleteMoab status is %{current_status}",
    UNEXPECTED_VERSION => "actual version (%{actual_version}) has unexpected relationship to %{db_obj_name} db version (%{db_obj_version}); ERROR!",
    VERSION_MATCHES => "actual version (%{actual_version}) matches %{addl} db version",
    ZIP_PART_CHECKSUM_MISMATCH => "replicated md5 mismatch on %{endpoint_name}: %{s3_key} catalog md5 (%{md5}) doesn't match the replicated md5 (%{replicated_checksum}) on %{bucket_name}",
    ZIP_PART_NOT_FOUND => "replicated part not found on %{endpoint_name}: %{s3_key} was not found on %{bucket_name}",
    ZIP_PARTS_COUNT_DIFFERS_FROM_ACTUAL => "%{version} on %{endpoint_name}: ZippedMoabVersion stated parts count (%{db_count}) doesn't match actual number of zip parts rows (%{actual_count})",
    ZIP_PARTS_COUNT_INCONSISTENCY => "%{version} on %{endpoint_name}: ZippedMoabVersion has variation in child parts_counts: %{child_parts_counts}",
    ZIP_PARTS_NOT_ALL_REPLICATED => "%{version} on %{endpoint_name}: not all ZippedMoabVersion parts are replicated yet: %{unreplicated_parts_list}",
    ZIP_PARTS_NOT_CREATED => "%{version} on %{endpoint_name}: no zip_parts exist yet for this ZippedMoabVersion"
  }.freeze

  WORKFLOW_REPORT_CODES = [
    ACTUAL_VERS_LT_DB_OBJ,
    CM_PO_VERSION_MISMATCH,
    DB_OBJ_ALREADY_EXISTS,
    DB_UPDATE_FAILED,
    FILE_NOT_IN_MANIFEST,
    FILE_NOT_IN_MOAB,
    FILE_NOT_IN_SIGNATURE_CATALOG,
    INVALID_MANIFEST,
    INVALID_MOAB,
    MANIFEST_NOT_IN_MOAB,
    MOAB_FILE_CHECKSUM_MISMATCH,
    MOAB_NOT_FOUND,
    SIGNATURE_CATALOG_NOT_IN_MOAB,
    UNABLE_TO_CHECK_STATUS,
    UNEXPECTED_VERSION
    # Temporary fix for workflow-service throwing exceptions
    # because some error reports from MoabReplicationAudit are too long
    # ZIP_PART_CHECKSUM_MISMATCH,
    # ZIP_PART_NOT_FOUND,
    # ZIP_PARTS_COUNT_DIFFERS_FROM_ACTUAL,
    # ZIP_PARTS_COUNT_INCONSISTENCY,
    # ZIP_PARTS_NOT_ALL_REPLICATED
  ].freeze

  HONEYBADGER_REPORT_CODES = [
    MOAB_FILE_CHECKSUM_MISMATCH,
    MOAB_NOT_FOUND,
    ZIP_PART_CHECKSUM_MISMATCH,
    ZIP_PART_NOT_FOUND,
    ZIP_PARTS_COUNT_DIFFERS_FROM_ACTUAL,
    ZIP_PARTS_COUNT_INCONSISTENCY,
    ZIP_PARTS_NOT_ALL_REPLICATED
  ].freeze

  DB_UPDATED_CODES = [
    CREATED_NEW_OBJECT,
    CM_STATUS_CHANGED
  ].freeze

  def self.logger_severity_level(result_code)
    case result_code
    when DB_OBJ_DOES_NOT_EXIST, ZIP_PARTS_NOT_CREATED, ZIP_PARTS_NOT_ALL_REPLICATED
      Logger::WARN
    when VERSION_MATCHES, ACTUAL_VERS_GT_DB_OBJ, CREATED_NEW_OBJECT, CM_STATUS_CHANGED, MOAB_CHECKSUM_VALID
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
    workflow_results = []
    result_array.each do |r|
      log_result(r, logger)
      if r.key?(INVALID_MOAB)
        # This error goes to diff workflow ('moab-valid') than 'preservation-audit'
        # also note that we shorten it because workflow service doesn't like really long strings
        # NOTE: this approach allows online Moab audit errors to block further accessioning (which is desired)
        #   - any WF error blocks further accessioning (i.e. can't open a new version)
        #   - we currently only send WF errors from audits of online moabs (replication audit problems don't show up in WF)
        msg = "#{string_prefix} || #{r.values.first}"
        WorkflowReporter.report_error(druid, actual_version, 'moab-valid', moab_storage_root, msg)
      elsif status_changed_to_ok?(r)
        WorkflowReporter.report_completed(druid, actual_version, 'moab-valid', moab_storage_root)
        WorkflowReporter.report_completed(druid, actual_version, 'preservation-audit', moab_storage_root)
      elsif WORKFLOW_REPORT_CODES.include?(r.keys.first)
        workflow_results << r
      end
      send_honeybadger_notification(r) if HONEYBADGER_REPORT_CODES.include?(r.keys.first)
    end
    report_errors_to_workflows(workflow_results)
    result_array
  end

  def contains_result_code?(code)
    result_array.detect { |result_hash| result_hash.key?(code) } != nil
  end

  def status_changed_to_ok?(result)
    /to ok$/.match(result[AuditResults::CM_STATUS_CHANGED]) != nil
  end

  def results_as_string(error_results)
    "#{string_prefix} #{error_results.map(&:values).flatten.join(' && ')}"
  end

  def to_json(*_args)
    { druid: druid, result_array: result_array }.to_json
  end

  private

  def result_hash(code, msg_args=nil)
    { code => result_code_msg(code, msg_args) }
  end

  # NOTE: this approach allows online Moab audit errors to block further accessioning (which is desired)
  #   - any WF error blocks further accessioning (i.e. can't open a new version)
  #   - we currently only send WF errors from audits of online moabs (replication audit problems don't show up in WF)
  def report_errors_to_workflows(error_results)
    return if error_results.empty?
    WorkflowReporter.report_error(druid, actual_version, 'preservation-audit', moab_storage_root, results_as_string(error_results))
  end

  def log_result(result, logger)
    severity = self.class.logger_severity_level(result.keys.first)
    logger.add(severity, "#{log_msg_prefix} #{result.values.first}")
  end

  def send_honeybadger_notification(result)
    Honeybadger.notify("#{log_msg_prefix} #{result.values.first}")
    events_client.create(
      type: 'preservation_audit_failure',
      data: {
        host: Socket.gethostname,
        invoked_by: 'preservation-catalog',
        storage_root: moab_storage_root&.name,
        actual_version: actual_version,
        check_name: check_name,
        error_result: result
      }
    )
  end

  def events_client
    Dor::Services::Client.object("druid:#{druid}").events # dor-services-app wants the namespaced druid
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

  def string_prefix
    @string_prefix ||= begin
      location_info = "actual location: #{moab_storage_root.name}" if moab_storage_root
      actual_version_info = "actual version: #{actual_version}" if actual_version
      "#{check_name} (#{location_info}; #{actual_version_info})"
    end
  end
end
