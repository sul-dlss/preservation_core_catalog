# frozen_string_literal: true

# Corresponds to a Moab-Version on a ZipEndpoint.
#   There will be individual parts (at least one) - see ZipPart.
# For a fully consistent system, given a PreservedObject, the number of associated
# ZippedMoabVersion objects should be:
#   preserved_object.current_version * number_of_zip_endpoints_for_preservation_policy
#
# @note Does not have size independent of part(s)
class ZippedMoabVersion < ApplicationRecord
  belongs_to :preserved_object, inverse_of: :zipped_moab_versions
  belongs_to :zip_endpoint, inverse_of: :zipped_moab_versions
  has_many :zip_parts, dependent: :destroy, inverse_of: :zipped_moab_version

  # Note: In the context of creating many ZMV rows, this may *attempt* to queue the same druid/version multiple times,
  # but queue locking easily prevents duplicates (and the job is idempotent anyway).
  after_create :replicate!

  validates :preserved_object, :version, :zip_endpoint, presence: true

  scope :by_druid, lambda { |druid|
    joins(:preserved_object).where(preserved_objects: { druid: druid })
  }

  # ideally, there should be only one distinct parts_count value among a set of sibling
  # zip_parts.  if there's variation in the count, that implies the zip was remade, and that
  # the part count differed between the zip invocations (which may imply a zip implementation
  # change, bitrot in the online Moab being archived, or some other unknown cause of drift).
  # hopefully this happens rarely or not at all, but an example scenario would be:
  # 1) zips get lost from cloud provider, 2) druid is re-queued for replication, no cached
  # zips available, 3) multi-part zip is remade, number of parts is fewer than prior zip/push,
  # 4) metadata on some existing part rows is updated with new (smaller) count, zips are pushed,
  # but old rows for prior push still exist with old (higher) count.
  def child_parts_counts
    zip_parts.group(:parts_count).pluck(:parts_count, Arel.sql('count(zip_parts.id)'))
  end

  def all_parts_replicated?
    zip_parts.count.positive? && zip_parts.all?(&:ok?)
  end

  # Send to asynchronous replication pipeline
  # @return [ZipmakerJob, nil] nil if unpersisted or parent PreservedObject has no replicatable Moab
  def replicate!
    return nil unless persisted?
    storage_location = preserved_object.moab_replication_storage_location
    return nil unless storage_location
    ZipmakerJob.perform_later(preserved_object.druid, version, storage_location)
  end
end
