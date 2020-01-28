# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StorageRootMigrationService do
  let(:to_storage_root) { create(:moab_storage_root) }

  let(:from_storage_root) { complete_moab1.moab_storage_root }

  let(:complete_moab1) {
    create(:complete_moab, status: 'ok',
                           last_moab_validation: Time.now,
                           last_checksum_validation: Time.now,
                           last_archive_audit: Time.now)
  }

  let(:complete_moab2) { create(:complete_moab, status: 'invalid_moab', moab_storage_root: from_storage_root) }

  let(:complete_moab3) { create(:complete_moab) }

  it 'migrates the storage root' do
    # Before migration
    expect(complete_moab1.moab_storage_root).to eq(complete_moab2.moab_storage_root)
    expect(complete_moab1.moab_storage_root).not_to eq(complete_moab3.moab_storage_root)

    druids = described_class.new(from_storage_root.name, to_storage_root.name).migrate
    expect(druids).to include(complete_moab1.preserved_object.druid, complete_moab2.preserved_object.druid)

    complete_moab1.reload
    complete_moab2.reload

    expect(complete_moab1.moab_storage_root).to eq(to_storage_root)
    expect(complete_moab2.moab_storage_root).to eq(to_storage_root)
  end

  it 'resets field values' do
    described_class.new(from_storage_root.name, to_storage_root.name).migrate

    complete_moab1.reload

    expect(complete_moab1.status).to eq('validity_unknown')
    expect(complete_moab1.last_moab_validation).to be_nil
    expect(complete_moab1.last_checksum_validation).to be_nil
    expect(complete_moab1.last_archive_audit).not_to be_nil
  end

  it 'does not migrate moabs on other storage roots' do
    # Before migration
    orig_complete_moab3_storage_root = complete_moab3.moab_storage_root

    described_class.new(from_storage_root.name, to_storage_root.name).migrate

    complete_moab3.reload

    expect(complete_moab3.moab_storage_root).to eq(orig_complete_moab3_storage_root)
  end
end
