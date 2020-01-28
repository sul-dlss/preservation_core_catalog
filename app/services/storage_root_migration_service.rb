# frozen_string_literal: true

# Migrates Complete Moab records to a new Moab Storate Root.
class StorageRootMigrationService
  def initialize(from_name, to_name)
    @from_name = from_name
    @to_name = to_name
  end

  # @return [Array<String>] druids of migrated moabs
  def migrate
    druids = []
    from_root.complete_moabs.find_each do |complete_moab|
      migrate_moab(complete_moab)
      druids << complete_moab.preserved_object.druid
    end
    druids
  end

  private

  def from_root
    @from_root ||= MoabStorageRoot.find_by!(name: @from_name)
  end

  def to_root
    @to_root ||= MoabStorageRoot.find_by!(name: @to_name)
  end

  def migrate_moab(moab)
    moab.moab_storage_root = to_root
    moab.status = 'validity_unknown' # This will queue a CV.
    # Fate of this to be determined by https://github.com/sul-dlss/preservation_catalog/issues/1329
    moab.last_moab_validation = nil
    moab.last_checksum_validation = nil
    moab.last_archive_audit = nil
    moab.save!
  end
end
