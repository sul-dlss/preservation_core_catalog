# frozen_string_literal: true

module Reporters
  # Helper for formatting messages.
  class MessageHelper
    def self.invalid_moab_message(check_name, version, storage_area, result)
      "#{string_prefix(check_name, version, storage_area)} || #{result.values.first}"
    end

    def self.results_as_message(check_name, version, storage_area, results)
      "#{string_prefix(check_name, version, storage_area)} #{results.map(&:values).flatten.join(' && ')}"
    end

    def self.string_prefix(check_name, version, storage_area)
      location_info = "actual location: #{storage_area}" if storage_area
      actual_version_info = "actual version: #{version}" if version
      "#{check_name} (#{location_info}; #{actual_version_info})"
    end
  end
end
