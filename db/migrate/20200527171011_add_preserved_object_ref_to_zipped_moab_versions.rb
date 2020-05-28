class AddPreservedObjectRefToZippedMoabVersions < ActiveRecord::Migration[6.0]
  def change
    add_reference :zipped_moab_versions, :preserved_object, foreign_key: true, null: true
    execute <<-SQL
UPDATE zipped_moab_versions AS zmv SET preserved_object_id = (SELECT preserved_object_id FROM complete_moabs AS cm WHERE cm.id = zmv.complete_moab_id);
    SQL
    change_column_null :zipped_moab_versions, :preserved_object_id, false
    remove_foreign_key :zipped_moab_versions, :complete_moabs
    remove_column :zipped_moab_versions, :complete_moab_id
  end
end
