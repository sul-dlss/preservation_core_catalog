# frozen_string_literal: true

require 'rails_helper'
require 'services/shared_examples_preserved_object_handler'

RSpec.describe MoabMovedHandler do
  let(:druid) { 'bj102hs9687' }
  let(:preserved_obj) { create(:preserved_object, druid: druid) }
  let(:ms_root) { MoabStorageRoot.find_by!(storage_location: 'spec/fixtures/storage_root01/sdr2objects') }
  let(:wrong_ms_root) { MoabStorageRoot.find_by!(storage_location: 'spec/fixtures/storage_root02/sdr2objects') }
  let(:complete_moab) { create(:complete_moab, version: 3, status: 'ok', preserved_object: preserved_obj, moab_storage_root: ms_root) }
  let(:results) { AuditResults.new(druid, nil, ms_root) }
  let(:handler) { described_class.new(complete_moab, results) }

  before do
    allow(WorkflowReporter).to receive(:report_error)
    allow(WorkflowReporter).to receive(:report_completed)
    allow(ChecksumValidationJob).to receive(:perform_later)
  end

  describe '#check_and_handle_moved_moab' do
    context 'CompleteMoab path does not match moab on disk' do
      before do
        complete_moab.moab_storage_root = wrong_ms_root
        complete_moab.status = 'online_moab_not_found'
        complete_moab.save!
      end

      it 'returns expected results' do
        handler.check_and_handle_moved_moab
        expect(results.report_results).to include(a_hash_including(AuditResults::CM_STORAGE_ROOT_CHANGED))
        expect(results.report_results).to include(a_hash_including(AuditResults::CM_STATUS_CHANGED =>
                                                        'CompleteMoab status changed from online_moab_not_found to validity_unknown'))
      end

      it 'changes the storage root' do
        expect(complete_moab.moab_storage_root).to eq wrong_ms_root
        handler.check_and_handle_moved_moab

        complete_moab.reload
        expect(complete_moab.moab_storage_root).to eq ms_root
      end

      it 'queues a checksum validation' do
        handler.check_and_handle_moved_moab
        expect(ChecksumValidationJob).to have_received(:perform_later).with(complete_moab)
      end
    end

    context 'Moab on disk not found' do
      let(:druid) { 'bj102hs9688' }

      it 'returns no results' do
        handler.check_and_handle_moved_moab
        expect(results.report_results).to be_empty
      end

      it 'does not change the storage root' do
        expect(complete_moab.moab_storage_root).to eq ms_root
        handler.check_and_handle_moved_moab
        expect(complete_moab.moab_storage_root).to eq ms_root
      end
    end

    context 'Moab on disk found but version mismatch' do
      before do
        complete_moab.moab_storage_root = wrong_ms_root
        complete_moab.version = 4
        complete_moab.save!
      end

      it 'returns no results' do
        handler.check_and_handle_moved_moab
        expect(results.report_results).to be_empty
      end

      it 'does not change the storage root' do
        expect(complete_moab.moab_storage_root).to eq wrong_ms_root
        handler.check_and_handle_moved_moab
        expect(complete_moab.moab_storage_root).to eq wrong_ms_root
      end
    end

    context 'Moab on disk found but invalid' do
      before do
        complete_moab.moab_storage_root = wrong_ms_root
        complete_moab.save!
        mock_validator = instance_double(Stanford::StorageObjectValidator)
        allow(mock_validator).to receive(:validation_errors).and_return(['An error'])
        allow(Stanford::StorageObjectValidator).to receive(:new).and_return(mock_validator)
      end

      it 'returns no results' do
        handler.check_and_handle_moved_moab
        expect(results.report_results).to be_empty
      end

      it 'does not change the storage root' do
        expect(complete_moab.moab_storage_root).to eq wrong_ms_root
        handler.check_and_handle_moved_moab
        expect(complete_moab.moab_storage_root).to eq wrong_ms_root
      end
    end
  end
end
