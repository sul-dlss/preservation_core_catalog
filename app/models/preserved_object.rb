# frozen_string_literal: true

##
# PreservedObject represents a master record tying together all
# concrete copies of an object that is being preserved.  It does not
# represent a specific stored instance on a specific node, but aggregates
# those instances.
class PreservedObject < ApplicationRecord
  PREFIX_RE = /druid:/i.freeze

  belongs_to :preservation_policy
  has_many :complete_moabs, dependent: :restrict_with_exception, autosave: true
  has_many :zipped_moab_versions, dependent: :restrict_with_exception, inverse_of: :preserved_object
  has_one :preserved_objects_primary_moab, dependent: :restrict_with_exception

  validates :druid,
            presence: true,
            uniqueness: true,
            length: { is: 11 },
            format: { with: /(?!#{PREFIX_RE})#{DruidTools::Druid.pattern}/ } # ?! group is a *negative* match
  validates :current_version, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :preservation_policy, null: false

  scope :without_complete_moabs, -> { left_outer_joins(:complete_moabs).where(complete_moabs: { id: nil }) }

  scope :archive_check_expired, lambda {
    joins(:preservation_policy)
      .where('(last_archive_audit + (archive_ttl * INTERVAL \'1 SECOND\')) < CURRENT_TIMESTAMP OR last_archive_audit IS NULL')
  }

  # This is where we make sure we have ZMV rows for all needed ZipEndpoints and versions.
  # Endpoints may have been added, so we must check all dimensions.
  # For *this* and *previous* versions, create any ZippedMoabVersion records which don't yet exist for
  # ZipEndpoints on the parent PreservedObject's PreservationPolicy.
  # @return [Array<ZippedMoabVersion>] the ZippedMoabVersion records that were created
  # @todo potential optimization: fold N which_need_archive_copy queries into one new query
  def create_zipped_moab_versions!
    params = (1..current_version).map do |v|
      ZipEndpoint.which_need_archive_copy(druid, v).map { |zep| { version: v, zip_endpoint: zep } }
    end.flatten.compact.uniq
    zipped_moab_versions.create!(params)
  end

  def as_json(*)
    super.except('id', 'preservation_policy_id')
  end

  # Queue a job that will check to see whether this PreservedObject has been
  # fully replicated to all target ZipEndpoints
  def audit_moab_version_replication!
    MoabReplicationAuditJob.perform_later(self)
  end

  # We need a specific copy of a moab from which to create the zip file(s) to send to the cloud.
  # Of those eligible for replication, use whichever was checksum validated most recently.
  # @return [String, nil] The storage location (storage_root/storage_trunk) where the Moab that should be replicated lives.
  def moab_replication_storage_location
    storage_location = moabs_eligible_for_replication.joins(:moab_storage_root).order(last_checksum_validation: :desc).limit(1).pluck(:storage_location).first
    # TODO: raise if no replicable location?  log?  nothing?
    return nil unless storage_location
    storage_location
  end

  private

  # a moab is eligible for replication if its status is 'ok' and its version is up to date with the latest seen for the object
  def moabs_eligible_for_replication
    CompleteMoab.joins(:preserved_object).where(preserved_object: self, complete_moabs: { status: 'ok', version: current_version })
  end
end
