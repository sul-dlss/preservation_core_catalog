# frozen_string_literal: true

# Migrates Complete Moab records to a new Moab Storate Root.
class StorageRootMigrationService
  def initialize(from_name, to_name)
    @from_name = from_name
    @to_name = to_name
  end

  # @return [Array<String>] druids of migrated moabs
  def migrate
    # no need to wrap in transaction, query not executed till e.g. #pluck or #update_all
    cm_on_from_root_relation = CompleteMoab.where(moab_storage_root: from_root)

    ApplicationRecord.transaction do
      druids = cm_on_from_root_relation.joins(:preserved_object).pluck(:druid)

      cm_on_from_root_relation.update_all(
        moab_storage_root_id: to_root.id,
        status: 'validity_unknown',
        last_moab_validation: nil,
        last_checksum_validation: nil
      )

      druids
    end
  end

  private

  def from_root
    @from_root ||= MoabStorageRoot.find_by!(name: @from_name)
  end

  def to_root
    @to_root ||= MoabStorageRoot.find_by!(name: @to_name)
  end
end
