# frozen_string_literal: true

module Reporters
  # Reports to logger.
  class LoggerReporter < BaseReporter
    def initialize(logger = nil)
      @logger = logger || Rails.logger
    end

    protected

    def handled_single_codes
      # Everything
      nil
    end

    def handle_completed(druid, _version, storage_area, check_name, result)
      log(druid, storage_area, check_name, result)
    end

    def handle_single_error(druid, _version, storage_area, check_name, result)
      log(druid, storage_area, check_name, result)
    end

    private

    attr_reader :logger

    def log(druid, storage_area, check_name, result)
      severity = logger_severity_level(result.keys.first)
      logger.add(severity, "#{check_name}(#{druid.delete_prefix('druid:')}, #{storage_area&.to_s}) #{result.values.first}")
    end

    def logger_severity_level(result_code)
      case result_code
      when AuditResults::DB_OBJ_DOES_NOT_EXIST, AuditResults::ZIP_PARTS_NOT_CREATED, AuditResults::ZIP_PARTS_NOT_ALL_REPLICATED
        Logger::WARN
      when AuditResults::VERSION_MATCHES, AuditResults::ACTUAL_VERS_GT_DB_OBJ, AuditResults::CREATED_NEW_OBJECT,
          AuditResults::CM_STATUS_CHANGED, AuditResults::MOAB_CHECKSUM_VALID
        Logger::INFO
      else
        Logger::ERROR
      end
    end
  end
end
