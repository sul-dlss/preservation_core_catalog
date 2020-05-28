class MoveLastArchiveAuditToPreservedObjects < ActiveRecord::Migration[6.0]
  disable_ddl_transaction! # note: this actually disables the wrapping transaction for the entire migration

  def change
    add_column :preserved_objects, :last_archive_audit, :datetime

    # and then we explicitly make this update transactional
    ApplicationRecord.transaction do
      execute <<-SQL
        UPDATE preserved_objects AS po SET last_archive_audit = (SELECT cm.last_archive_audit FROM complete_moabs AS cm WHERE cm.preserved_object_id = po.id);
      SQL
      add_index :preserved_objects, :last_archive_audit
    end

    remove_column :complete_moabs, :last_archive_audit
  end
end
