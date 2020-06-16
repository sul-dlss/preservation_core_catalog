# frozen_string_literal: true

# Checks whether a PreservedObject has all versions/parts replicated for each of its target endpoints.
# @note Enqueues a check per endpoint
# @example usage
#   MoabReplicationAuditJob.perform_later(preserved_object)
class MoabReplicationAuditJob < ApplicationJob
  queue_as :moab_replication_audit

  # @param [PreservedObject] for which to verify presence of the archive zips we think we've replicated (and possibly backfill those we haven't)
  def perform(preserved_object)
    backfill_missing_zmvs if Settings.replication.audit_should_backfill
    ZipEndpoint
      .includes(:zipped_moab_versions)
      .where(zipped_moab_versions: { preserved_object: preserved_object }).each do |endpoint|
        PartReplicationAuditJob.perform_later(preserved_object, endpoint)
      end
    preserved_object.update(last_archive_audit: Time.current)
  end

  private

  def backfill_missing_zmvs
    preserved_object = arguments.first
    zmvs = preserved_object.create_zipped_moab_versions!
    return if zmvs.empty?
    Audit::CatalogToArchive.logger.warn(
      "#{self.class}: #{preserved_object.druid} backfilled #{zmvs.count} ZippedMoabVersions: #{format_zmvs(zmvs)}"
    )
  end

  # @return [String] a potentially large message
  def format_zmvs(zmvs)
    zmvs.map { |bz| "#{bz.version} to #{bz.zip_endpoint.endpoint_name}" }.sort.join('; ')
  end
end
