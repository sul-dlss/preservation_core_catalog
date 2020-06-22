# frozen_string_literal: true

module Reporters
  # Base class for Reporters.
  class BaseReporter
    # Report errors.
    # The reporter will only report the errors that it handles (based on the code). It may also merge errors and report once.
    # @param [String] druid (without druid: prefix)
    # @param [Integer] version
    # @param [MoabStorageRoot, ZipEndpoint] storage_area the MoabStorageRoot or ZipEndpoint on which the moab or zipped moab version resides
    # @param [String] check_name, e.g., validate_checksums
    # @param [[Hash<String, String>]] results, an array of hashes with the code as key and message as value.
    def report_errors(druid:, version:, storage_area:, check_name:, results:)
      merge_results = []
      results.each do |result|
        handle_single_error(namespaced_druid(druid), version, storage_area, check_name, result) if handles?(handled_single_codes, result)
        merge_results << result if handles?(handled_merge_codes, result)
      end
      handle_merge_error(namespaced_druid(druid), version, storage_area, check_name, merge_results) if merge_results.any?
    end

    # Report completed.
    # The reporter will only report for the codes that it handles.
    # @param [String] druid (without druid: prefix)
    # @param [Integer] version
    # @param [MoabStorageRoot] storage_area
    # @param [String] check_name, e.g., validate_checksums
    # @param [Hash<String, String>] result, a hash with the code as key and message as value.
    def report_completed(druid:, version:, storage_area:, check_name:, result:)
      handle_completed(namespaced_druid(druid), version, storage_area, check_name, result)
    end

    protected

    def handled_single_codes
      # No codes
      []
    end

    def handled_merge_codes
      # No codes
      []
    end

    def handle_completed(_druid, _version, _storage_area, _check_name, _result)
      raise NotImplementedError
    end

    def handle_single_error(_druid, _version, _storage_area, _check_name, _result)
      raise NotImplementedError
    end

    def handle_merge_error(_druid, _version, _storage_area, _check_name, _results)
      raise NotImplementedError
    end

    private

    def namespaced_druid(druid)
      "druid:#{druid}"
    end

    def handles?(handled_codes, result)
      handled_codes.nil? || handled_codes.include?(result.keys.first)
    end
  end
end
