# frozen_string_literal: true

##
# CompleteMoab represents a concrete instance of a PreservedObject across ALL versions, in physical storage.
class CompleteMoab < ApplicationRecord
  # @note Hash values cannot be modified without migrating any associated persisted data.
  # @see [enum docs] http://api.rubyonrails.org/classes/ActiveRecord/Enum.html
  enum status: {
    'ok' => 0,
    'invalid_moab' => 1,
    'invalid_checksum' => 2,
    'online_moab_not_found' => 3,
    'unexpected_version_on_storage' => 4,
    'validity_unknown' => 6
  }

  after_create :create_zipped_moab_versions!
  after_update :create_zipped_moab_versions!, if: :saved_change_to_version? # an ActiveRecord dynamic method
  after_save :validate_checksums!, if: proc { |cm| cm.saved_change_to_status? && cm.validity_unknown? }

  belongs_to :preserved_object, inverse_of: :complete_moabs
  belongs_to :moab_storage_root, inverse_of: :complete_moabs
  belongs_to :from_moab_storage_root, class_name: 'MoabStorageRoot', required: false

  # NOTE: we'd like to check if there is a different complete_moab for the preserved_object and
  #  assign the other complete_moab to preserved_objects_primary_moab
  has_one :preserved_objects_primary_moab, dependent: :destroy

  validates :moab_storage_root, :preserved_object, :status, :version, presence: true
  validates_uniqueness_of :preserved_object_id, scope: [:moab_storage_root_id]
  # NOTE: size here is approximate and not used for fixity checking
  validates :size, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  scope :by_druid, lambda { |druid|
    joins(:preserved_object).where(preserved_objects: { druid: druid })
  }

  scope :by_storage_root, lambda { |moab_storage_root|
    joins(:moab_storage_root).where(moab_storage_root: moab_storage_root)
  }

  scope :least_recent_version_audit, lambda { |last_checked_b4_date|
    where('last_version_audit IS NULL or last_version_audit < ?', normalize_date(last_checked_b4_date))
  }

  scope :fixity_check_expired, lambda {
    joins(:preserved_object)
      .joins(
        'INNER JOIN preservation_policies'\
        ' ON preservation_policies.id = preserved_objects.preservation_policy_id'\
        ' AND (last_checksum_validation + (fixity_ttl * INTERVAL \'1 SECOND\')) < CURRENT_TIMESTAMP'\
        ' OR last_checksum_validation IS NULL'
      )
  }

  # TODO: create_missing_zipped_moab_versions! would be a better name
  delegate :create_zipped_moab_versions!, to: :preserved_object

  # Send to asynchronous checksum validation pipeline
  def validate_checksums!
    ChecksumValidationJob.perform_later(self)
  end

  # TODO: may become obsolete
  def replicatable_status?
    ok?
  end

  def update_audit_timestamps(moab_validated, version_audited)
    t = Time.current
    self.last_moab_validation = t if moab_validated
    self.last_version_audit = t if version_audited
  end

  # @param [Boolean] moab_validated whether validation has been run (regardless of result)
  # @param [Integer] new_version
  # @param [Integer] new_size is expected to be numeric if provided
  def upd_audstamps_version_size(moab_validated, new_version, new_size = nil)
    self.version = new_version
    self.size = new_size if new_size
    update_audit_timestamps(moab_validated, true)
  end

  def matches_po_current_version?
    version == preserved_object.current_version
  end

  # This method can be used to update the CompleteMoab record in Preservation Catalog when the
  # corresponding Moab directory on the file system has moved from its old storage root to a new
  # one (e.g. when migrating off of old storage hardware in bulk, or when manually moving a Moab
  # that's growing to a storage root with more space).
  #
  # Sets status to 'validity_unknown' and clears validation details, under the assumption that
  # the moab moved across file systems, resulting in newly written bits and a need for revalidation.
  #
  # Like other update methods in this class, it leaves saving to the caller.
  #
  # @param [MoabStorageRoot] to_root the storage root to which the Moab's been moved on the file system
  # @return [CompleteMoab] the instance on which the method was called
  def migrate_moab(to_root)
    self.from_moab_storage_root = moab_storage_root
    self.moab_storage_root = to_root
    self.status = 'validity_unknown' # an after_save hook watches for this status and queues CV
    self.status_details = nil
    self.last_moab_validation = nil
    self.last_checksum_validation = nil
    self.last_version_audit = nil
    self
  end

  def self.normalize_date(timestamp)
    return timestamp if timestamp.is_a?(Time) || timestamp.is_a?(ActiveSupport::TimeWithZone)
    Time.parse(timestamp).utc
  end

  # Sort the given relation by last_version_audit, nulls first.
  def self.order_last_version_audit(active_record_relation)
    # possibly non-obvious: IS NOT NULL evaluates to 0 for nulls and 1 for non-nulls; thus, this
    # sorts nulls (0) before non-nulls (1), and non-nulls are then sorted by last_version_audit.
    # standard SQL doesn't have a NULLS FIRST sort built in.
    active_record_relation.order(Arel.sql('last_version_audit IS NOT NULL, last_version_audit ASC'))
  end

  # Sort the given relation by last_checksum_validation, nulls first.
  def self.order_fixity_check_expired(active_record_relation)
    # possibly non-obvious: IS NOT NULL evaluates to 0 for nulls and 1 for non-nulls; thus, this
    # sorts nulls (0) before non-nulls (1), and non-nulls are then sorted by last_checksum_validation.
    # standard SQL doesn't have a NULLS FIRST sort built in.
    active_record_relation.order(Arel.sql('last_checksum_validation IS NOT NULL, last_checksum_validation ASC'))
  end
end
