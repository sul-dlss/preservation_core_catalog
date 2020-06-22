# frozen_string_literal: true

##
# Metadata about a Moab storage root (a POSIX file system which contains Moab objects).
class MoabStorageRoot < ApplicationRecord
  has_many :complete_moabs, dependent: :restrict_with_exception
  has_many :migrated_moabs, class_name: 'CompleteMoab', foreign_key: :from_moab_storage_root_id
  has_many :preserved_objects, through: :complete_moabs
  has_and_belongs_to_many :preservation_policies

  validates :name, presence: true, uniqueness: true
  validates :storage_location, presence: true, uniqueness: true

  scope :preserved_objects, lambda {
    joins(complete_moabs: [:preserved_object])
  }

  # Use a queue to validate CompleteMoab objects
  def validate_expired_checksums!
    cms = complete_moabs.fixity_check_expired
    Rails.logger.info "MoabStorageRoot #{id} (#{name}), # of complete_moabs to be checksum validated: #{cms.count}"
    cms.find_each(&:validate_checksums!)
  end

  # Use a queue to check all associated CompleteMoab objects for C2M
  def c2m_check!(last_checked_b4_date = Time.current)
    complete_moabs.least_recent_version_audit(last_checked_b4_date).find_each do |cm|
      CatalogToMoabJob.perform_later(cm)
    end
  end

  # Use a queue to ensure each druid on this root's directory is in the catalog database
  def m2c_check!
    Stanford::MoabStorageDirectory.find_moab_paths(storage_location) do |druid, _path, _match|
      MoabToCatalogJob.perform_later(self, druid)
    end
  end

  def to_s
    name
  end

  # Iterates over the storage roots enumerated in settings, creating a MoabStorageRoot for
  # each if it doesn't already exist.  Besides db/seeds.rb, this should be used rarely, if at all.
  # @param preservation_policies [Enumerable<PreservationPolicy>] list of preservation policies
  #   which any newly created moab_storage_roots implement.
  # @return [Array<MoabStorageRoot>] MoabStorageRoots for each one defined in the config (found or created)
  # @note this adds new entries from the config, and leaves existing entries alone, but won't delete anything.
  def self.seed_from_config(preservation_policies)
    Settings.storage_root_map.default.each do |storage_root_name, storage_root_location|
      find_or_create_by!(name: storage_root_name.to_s) do |sr|
        sr.storage_location = File.join(storage_root_location, Settings.moab.storage_trunk)
        sr.preservation_policies = preservation_policies
      end
    end
  end
end
