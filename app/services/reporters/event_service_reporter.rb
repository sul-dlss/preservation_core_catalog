# frozen_string_literal: true

module Reporters
  # Reports to DOR Event Service.
  class EventServiceReporter < BaseReporter
    protected

    def handled_single_codes
      [
        AuditResults::INVALID_MOAB
      ]
    end

    def handled_merge_codes
      [
        AuditResults::ACTUAL_VERS_LT_DB_OBJ,
        AuditResults::CM_PO_VERSION_MISMATCH,
        AuditResults::DB_OBJ_ALREADY_EXISTS,
        AuditResults::DB_UPDATE_FAILED,
        AuditResults::FILE_NOT_IN_MANIFEST,
        AuditResults::FILE_NOT_IN_MOAB,
        AuditResults::FILE_NOT_IN_SIGNATURE_CATALOG,
        AuditResults::INVALID_MANIFEST,
        AuditResults::MANIFEST_NOT_IN_MOAB,
        AuditResults::MOAB_FILE_CHECKSUM_MISMATCH,
        AuditResults::MOAB_NOT_FOUND,
        AuditResults::SIGNATURE_CATALOG_NOT_IN_MOAB,
        AuditResults::UNABLE_TO_CHECK_STATUS,
        AuditResults::UNEXPECTED_VERSION,
        AuditResults::ZIP_PART_CHECKSUM_MISMATCH,
        AuditResults::ZIP_PART_NOT_FOUND,
        AuditResults::ZIP_PARTS_COUNT_DIFFERS_FROM_ACTUAL,
        AuditResults::ZIP_PARTS_COUNT_INCONSISTENCY,
        AuditResults::ZIP_PARTS_NOT_ALL_REPLICATED
      ].freeze
    end

    def handle_completed(druid, version, storage_area, _check_name, _result)
      create_success_event(druid, version, 'moab-valid', storage_area)
      create_success_event(druid, version, 'preservation-audit', storage_area)
    end

    def handle_single_error(druid, version, storage_area, check_name, result)
      error_message = MessageHelper.invalid_moab_message(check_name, version, storage_area, result)
      create_error_event(druid, version, 'moab-valid', storage_area, error_message)
    end

    def handle_merge_error(druid, version, storage_area, check_name, results)
      error_message = MessageHelper.results_as_message(check_name, version, storage_area, results)
      create_error_event(druid, version, 'preservation-audit', storage_area, error_message)
    end

    private

    def events_client_for(druid)
      Dor::Services::Client.object(druid).events
    end

    def create_success_event(druid, version, process_name, storage_area)
      events_client_for(druid).create(
        type: 'preservation_audit_success',
        data: {
          host: Socket.gethostname,
          invoked_by: 'preservation-catalog',
          storage_area: storage_area&.to_s,
          actual_version: version,
          check_name: process_name
        }
      )
    end

    def create_error_event(druid, version, process_name, storage_area, error_message)
      events_client_for(druid).create(
        type: 'preservation_audit_failure',
        data: {
          host: Socket.gethostname,
          invoked_by: 'preservation-catalog',
          storage_area: storage_area&.to_s,
          actual_version: version,
          check_name: process_name,
          error: error_message
        }
      )
    end
  end
end
