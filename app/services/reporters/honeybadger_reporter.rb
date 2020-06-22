# frozen_string_literal: true

module Reporters
  # Reports to Honeybadger.
  class HoneybadgerReporter < BaseReporter
    protected

    def handled_single_codes
      [
        AuditResults::MOAB_FILE_CHECKSUM_MISMATCH,
        AuditResults::MOAB_NOT_FOUND,
        AuditResults::ZIP_PART_CHECKSUM_MISMATCH,
        AuditResults::ZIP_PART_NOT_FOUND,
        AuditResults::ZIP_PARTS_COUNT_DIFFERS_FROM_ACTUAL,
        AuditResults::ZIP_PARTS_COUNT_INCONSISTENCY,
        AuditResults::ZIP_PARTS_NOT_ALL_REPLICATED
      ].freeze
    end

    def handle_completed(druid, version, storage_area, check_name, result)
      # Pass
    end

    def handle_single_error(druid, _version, storage_area, check_name, result)
      Honeybadger.notify("#{check_name}(#{druid}, #{storage_area&.to_s}) #{result.values.first}")
    end
  end
end
