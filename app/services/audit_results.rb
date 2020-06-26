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
    ACTUAL_VERS_GT_DB_OBJ => 'actual version (%{actual_version}) greater than ' \
      '%{db_obj_name} db version (%{db_obj_version})',
    ACTUAL_VERS_LT_DB_OBJ => 'actual version (%{actual_version}) less than ' \
      '%{db_obj_name} db version (%{db_obj_version}); ERROR!',
    CM_PO_VERSION_MISMATCH => 'CompleteMoab online Moab version %{cm_version} ' \
      'does not match PreservedObject current_version %{po_version}',
    CM_STATUS_CHANGED => 'CompleteMoab status changed from %{old_status} to %{new_status}',
    CREATED_NEW_OBJECT => 'added object to db as it did not exist',
    DB_OBJ_ALREADY_EXISTS => '%{addl} db object already exists',
    DB_OBJ_DOES_NOT_EXIST => '%{addl} db object does not exist',
    DB_UPDATE_FAILED => 'db update failed: %{addl}',
    FILE_NOT_IN_MANIFEST => 'Moab file %{file_path} was not found in Moab manifest %{manifest_file_path}',
    FILE_NOT_IN_MOAB => '%{manifest_file_path} refers to file (%{file_path}) not found in Moab',
    FILE_NOT_IN_SIGNATURE_CATALOG => 'Moab file %{file_path} was not found in ' \
      'Moab signature catalog %{signature_catalog_path}',
    INVALID_ARGUMENTS => 'encountered validation error(s): %{addl}',
    INVALID_MANIFEST => 'unable to parse %{manifest_file_path} in Moab',
    INVALID_MOAB => 'Invalid Moab, validation errors: %{addl}',
    MANIFEST_NOT_IN_MOAB => '%{manifest_file_path} not found in Moab',
    MOAB_CHECKSUM_VALID => 'checksum(s) match',
    MOAB_FILE_CHECKSUM_MISMATCH => 'checksums or size for %{file_path} version ' \
      '%{version} do not match entry in latest signatureCatalog.xml.',
    MOAB_NOT_FOUND => 'db CompleteMoab (created %{db_created_at}; last updated ' \
      '%{db_updated_at}) exists but Moab not found',
    SIGNATURE_CATALOG_NOT_IN_MOAB => '%{signature_catalog_path} not found in Moab',
    UNABLE_TO_CHECK_STATUS => 'unable to validate when CompleteMoab status is %{current_status}',
    UNEXPECTED_VERSION => 'actual version (%{actual_version}) has unexpected ' \
      'relationship to %{db_obj_name} db version (%{db_obj_version}); ERROR!',
    VERSION_MATCHES => 'actual version (%{actual_version}) matches %{addl} db version',
    ZIP_PART_CHECKSUM_MISMATCH => 'replicated md5 mismatch on %{endpoint_name}: ' \
      "%{s3_key} catalog md5 (%{md5}) doesn't match the replicated md5 " \
      '(%{replicated_checksum}) on %{bucket_name}',
    ZIP_PART_NOT_FOUND => 'replicated part not found on %{endpoint_name}: ' \
      '%{s3_key} was not found on %{bucket_name}',
    ZIP_PARTS_COUNT_DIFFERS_FROM_ACTUAL => '%{version} on %{endpoint_name}: ' \
      "ZippedMoabVersion stated parts count (%{db_count}) doesn't match actual " \
      'number of zip parts rows (%{actual_count})',
    ZIP_PARTS_COUNT_INCONSISTENCY => '%{version} on %{endpoint_name}: ' \
      'ZippedMoabVersion has variation in child parts_counts: %{child_parts_counts}',
    ZIP_PARTS_NOT_ALL_REPLICATED => '%{version} on %{endpoint_name}: not all ' \
      'ZippedMoabVersion parts are replicated yet: %{unreplicated_parts_list}',
    ZIP_PARTS_NOT_CREATED => '%{version} on %{endpoint_name}: no zip_parts exist yet for this ZippedMoabVersion'
  }.freeze

  DB_UPDATED_CODES = [
    CREATED_NEW_OBJECT,
    CM_STATUS_CHANGED
  ].freeze

  attr_reader :result_array, :druid, :storage_area, :logger
  attr_accessor :actual_version, :check_name

  def initialize(druid, actual_version, storage_area, check_name = nil, logger: nil)
    @druid = druid
    @actual_version = actual_version
    @storage_area = storage_area
    @check_name = check_name
    @result_array = []
    @logger = logger
  end

  def add_result(code, msg_args = nil)
    result_array << result_hash(code, msg_args)
  end

  # used when updates wrapped in transaction fail, and there is a need to ensure there is no db updated result
  def remove_db_updated_results
    result_array.delete_if { |res_hash| DB_UPDATED_CODES.include?(res_hash.keys.first) }
  end

  def report_results
    # Report completed
    completed_results = result_array.select { |result| status_changed_to_ok?(result) }
    report_completed(completed_results)

    # Report errors
    error_results = result_array - completed_results
    report_errors(error_results)
    result_array
  end

  def contains_result_code?(code)
    result_array.detect { |result_hash| result_hash.key?(code) } != nil
  end

  def status_changed_to_ok?(result)
    /to ok$/.match(result[AuditResults::CM_STATUS_CHANGED]) != nil
  end

  def results_as_string
    "#{string_prefix} #{result_array.map(&:values).flatten.join(' && ')}"
  end

  def to_json(*_args)
    { druid: druid, result_array: result_array }.to_json
  end

  private

  def reporters
    @reporters ||= [
      Reporters::LoggerReporter.new(logger),
      Reporters::HoneybadgerReporter.new,
      Reporters::WorkflowReporter.new,
      Reporters::EventServiceReporter.new
    ].freeze
  end

  def report_errors(results)
    reporters.each do |reporter|
      reporter.report_errors(druid: druid, version: actual_version, storage_area: storage_area, check_name: check_name, results: results)
    end
  end

  def report_completed(results)
    reporters.each do |reporter|
      results.each do |result|
        reporter.report_completed(druid: druid, version: actual_version, storage_area: storage_area, check_name: check_name, result: result)
      end
    end
  end

  def result_hash(code, msg_args = nil)
    { code => result_code_msg(code, msg_args) }
  end

  def result_code_msg(code, addl = nil)
    arg_hash = { actual_version: actual_version }
    if addl.is_a?(Hash)
      arg_hash.merge!(addl)
    else
      arg_hash[:addl] = addl
    end
    RESPONSE_CODE_TO_MESSAGES[code] % arg_hash
  end

  def string_prefix
    @string_prefix ||= begin
      location_info = "actual location: #{storage_area}" if storage_area
      actual_version_info = "actual version: #{actual_version}" if actual_version
      "#{check_name} (#{location_info}; #{actual_version_info})"
    end
  end
end
