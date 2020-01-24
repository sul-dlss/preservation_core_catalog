# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Audit::CatalogToMoab do
  let(:last_checked_version_b4_date) { (Time.now.utc - 1.day).iso8601 }
  let(:storage_location) { 'spec/fixtures/storage_root01/sdr2objects' }
  let(:druid) { 'bj102hs9687' }
  let(:c2m) { described_class.new(comp_moab) }
  let(:mock_sov) { instance_double(Stanford::StorageObjectValidator) }
  let(:po) { create(:preserved_object_fixture, druid: druid) }
  let(:ms_root) { MoabStorageRoot.find_by!(storage_location: storage_location) }
  let(:comp_moab) do
    MoabStorageRoot.find_by!(storage_location: storage_location).complete_moabs.find_by!(preserved_object: po)
  end
  let(:logger_double) { instance_double(Logger, info: nil, error: nil, add: nil) }
  let(:results_double) do
    instance_double(AuditResults, add_result: nil, :actual_version= => nil, :check_name= => nil, report_results: nil)
  end

  before do
    allow(WorkflowReporter).to receive(:report_error)
    allow(c2m).to receive(:logger).and_return(logger_double) # silence log output
  end

  describe '#initialize' do
    it 'sets attributes' do
      expect(c2m.complete_moab).to eq comp_moab
      expect(c2m.druid).to eq druid
      expect(c2m.results).to be_an_instance_of AuditResults
    end
  end

  describe '#logger' do
    it 'returns a logger object' do
      allow(c2m).to receive(:logger).and_call_original # undo doubling for 1 test
      expect(c2m.logger).to be_a(Logger)
    end
  end

  describe '#check_catalog_version' do
    let(:object_dir) { "#{storage_location}/#{DruidTools::Druid.new(druid).tree.join('/')}" }

    before { comp_moab.ok! }

    it 'instantiates Moab::StorageObject from druid and storage_location' do
      expect(Moab::StorageObject).to receive(:new).with(druid, a_string_matching(object_dir)).and_call_original
      c2m.check_catalog_version
    end

    it 'gets the current version on disk from the Moab::StorageObject' do
      moab = instance_double(Moab::StorageObject, object_pathname: object_dir, exist?: true)
      allow(Moab::StorageObject).to receive(:new).with(druid, String).and_return(moab)
      expect(moab).to receive(:current_version_id).and_return(3)
      c2m.check_catalog_version
    end

    it 'calls CompleteMoab.update_audit_timestamps' do
      expect(comp_moab).to receive(:update_audit_timestamps).with(anything, true)
      c2m.check_catalog_version
    end

    it 'calls CompleteMoab.save!' do
      expect(comp_moab).to receive(:save!)
      c2m.check_catalog_version
    end

    it 'calls AuditResults.report_results' do
      c2m.instance_variable_set(:@results, results_double)
      expect(c2m.results).to receive(:report_results)
      c2m.check_catalog_version
    end

    it 'calls online_moab_found?' do
      expect(c2m).to receive(:online_moab_found?).and_return(true)
      c2m.check_catalog_version
    end

    context 'moab is nil (exists in catalog but not online at all)' do
      let(:moab) { instance_double(Moab::StorageObject) }

      before do
        allow(Moab::StorageObject).to receive(:new).with(druid, String).and_return(nil)
        allow(Moab::StorageServices).to receive(:find_storage_object).with(druid).and_return(moab)
        allow(moab).to receive(:exist?).and_return(false)
      end

      it 'adds a MOAB_NOT_FOUND result' do
        c2m.instance_variable_set(:@results, results_double)
        expect(c2m.results).to receive(:add_result).with(
          AuditResults::MOAB_NOT_FOUND, db_created_at: anything, db_updated_at: anything
        )
        expect(c2m.results).to receive(:add_result).with(
          AuditResults::CM_STATUS_CHANGED, old_status: "ok", new_status: "online_moab_not_found"
        )
        c2m.check_catalog_version
      end

      context 'updates status correctly' do
        [
          'validity_unknown',
          'ok',
          'online_moab_not_found',
          'invalid_moab',
          'unexpected_version_on_storage',
          'invalid_checksum'
        ].each do |orig_status|
          it "had #{orig_status}, should now have ONLINE_MOAB_NOT_FOUND_STATUS" do
            comp_moab.status = orig_status
            comp_moab.save!
            c2m.check_catalog_version
            expect(comp_moab.reload.status).to eq 'online_moab_not_found'
          end
        end
      end

      context 'DB transaction handling' do
        it 'on transaction failure, completes without raising error, removes CM_STATUS_CHANGED result code' do
          allow(comp_moab).to receive(:save!).and_raise(ActiveRecord::ConnectionTimeoutError)
          c2m.check_catalog_version
          expect(c2m.results.result_array).to include(a_hash_including(AuditResults::MOAB_NOT_FOUND))
          expect(c2m.results.result_array).not_to include(a_hash_including(AuditResults::CM_STATUS_CHANGED))
          expect(comp_moab.reload.status).not_to eq 'online_moab_not_found'
        end
      end
    end

    context 'moab is nil (exists in catalog but online in a different location)' do
      let(:wrong_ms_root) { MoabStorageRoot.find_by!(storage_location: 'spec/fixtures/storage_root02/sdr2objects') }

      before do
        comp_moab.ok!
        comp_moab.moab_storage_root = wrong_ms_root
        comp_moab.save!
        c2m.instance_variable_set(:@results, results_double)
      end

      it 'adds a MOAB_NOT_FOUND and CM_STORAGE_ROOT result' do
        expect(c2m.results).to receive(:add_result).with(
          AuditResults::MOAB_NOT_FOUND, db_created_at: anything, db_updated_at: anything
        )
        expect(c2m.results).to receive(:add_result).with(
          AuditResults::CM_STATUS_CHANGED, old_status: "ok", new_status: "online_moab_not_found"
        )
        expect(c2m.results).to receive(:add_result).with(
          AuditResults::CM_STORAGE_ROOT_CHANGED, old_storage_root: 'spec/fixtures/storage_root02/sdr2objects',
                                                 new_storage_root: 'spec/fixtures/storage_root01/sdr2objects'
        )
        expect(c2m.results).to receive(:add_result).with(
          AuditResults::CM_STATUS_CHANGED, old_status: "online_moab_not_found", new_status: "validity_unknown"
        )
        c2m.check_catalog_version
      end

      it 'changes the storage root' do
        c2m.check_catalog_version
        expect(comp_moab.moab_storage_root).to eq ms_root
      end
    end

    context 'complete_moab version != current_version of preserved_object' do
      before do
        comp_moab.version = 666
        c2m.instance_variable_set(:@results, results_double)
      end

      it 'adds a CM_PO_VERSION_MISMATCH result and finishes processing' do
        expect(c2m.results).to receive(:add_result).with(
          AuditResults::CM_PO_VERSION_MISMATCH,
          cm_version: comp_moab.version,
          po_version: comp_moab.preserved_object.current_version
        )
        expect(Moab::StorageObject).not_to receive(:new).with(druid, a_string_matching(object_dir))
        c2m.check_catalog_version
      end

      it 'calls AuditResults.report_results' do
        expect(c2m.results).to receive(:report_results)
        c2m.check_catalog_version
      end
    end

    context 'catalog version == moab version (happy path)' do
      it 'adds a VERSION_MATCHES result' do
        c2m.instance_variable_set(:@results, results_double)
        expect(c2m.results).to receive(:add_result).with(AuditResults::VERSION_MATCHES, 'CompleteMoab')
        c2m.check_catalog_version
      end

      context 'check whether CompleteMoab already has a status other than OK_STATUS, re-check status if so;' do
        it "had OK_STATUS, should keep OK_STATUS" do
          comp_moab.ok!
          allow(c2m).to receive(:moab_validation_errors).and_return([])
          c2m.check_catalog_version
          expect(comp_moab.reload).to be_ok
        end

        [
          'validity_unknown',
          'online_moab_not_found',
          'invalid_moab',
          'unexpected_version_on_storage'
        ].each do |orig_status|
          it "had #{orig_status}, should now have validity_unknown" do
            comp_moab.status = orig_status
            comp_moab.save!
            allow(c2m).to receive(:moab_validation_errors).and_return([])
            c2m.check_catalog_version
            expect(comp_moab.reload).to be_validity_unknown
          end
        end

        # 'ok' intentionally omitted, since we don't check status on disk
        # if versions match
        [
          'validity_unknown',
          'online_moab_not_found',
          'invalid_moab',
          'unexpected_version_on_storage'
        ].each do |orig_status|
          it "had #{orig_status}, should now have INVALID_MOAB_STATUS" do
            comp_moab.status = orig_status
            comp_moab.save!
            allow(c2m).to receive(:moab_validation_errors).and_return(
              [{ Moab::StorageObjectValidator::MISSING_DIR => 'err msg' }]
            )
            c2m.check_catalog_version
            expect(comp_moab.reload.status).to eq 'invalid_moab'
          end
        end

        context 'started with INVALID_CHECKSUM_STATUS' do
          before { comp_moab.invalid_checksum! }

          it 'remains in INVALID_CHECKSUM_STATUS' do
            allow(c2m).to receive(:moab_validation_errors).and_return(
              [{ Moab::StorageObjectValidator::MISSING_DIR => 'err msg' }]
            )
            c2m.check_catalog_version
            expect(comp_moab.reload.status).to eq 'invalid_checksum'
          end

          it 'has an AuditResults entry indicating inability to check the given status' do
            c2m.check_catalog_version
            expect(c2m.results.contains_result_code?(AuditResults::UNABLE_TO_CHECK_STATUS)).to eq true
          end
        end
      end
    end

    context 'catalog version < moab version' do
      before do
        moab = instance_double(Moab::StorageObject, size: 666, object_pathname: object_dir, exist?: true)
        allow(Moab::StorageObject).to receive(:new).with(druid, instance_of(String)).and_return(moab)
        allow(moab).to receive(:current_version_id).and_return(4)
      end

      it 'calls PreservedObjectHandler.update_version_after_validation' do
        pohandler = instance_double(PreservedObjectHandler)
        expect(PreservedObjectHandler).to receive(:new).and_return(pohandler)
        expect(pohandler).to receive(:update_version_after_validation)
        c2m.check_catalog_version
      end

      context 'runs validations other than checksum' do
        context 'no validation errors' do
          [
            'validity_unknown',
            'ok',
            'online_moab_not_found',
            'invalid_moab',
            'unexpected_version_on_storage'
          ].each do |orig_status|
            it "#{orig_status} changes to validity_unknown" do
              comp_moab.status = orig_status
              comp_moab.save!
              allow(mock_sov).to receive(:validation_errors).and_return([])
              allow(Stanford::StorageObjectValidator).to receive(:new).and_return(mock_sov)
              c2m.check_catalog_version
              expect(comp_moab.reload).to be_validity_unknown
            end
          end
        end

        context 'finds validation errors' do
          [
            'validity_unknown',
            'ok',
            'online_moab_not_found',
            'unexpected_version_on_storage'
          ].each do |orig_status|
            it "#{orig_status} changes to INVALID_MOAB_STATUS" do
              comp_moab.status = orig_status
              comp_moab.save!
              allow(mock_sov).to receive(:validation_errors).and_return(
                [{ Moab::StorageObjectValidator::MISSING_DIR => 'err msg' }]
              )
              allow(Stanford::StorageObjectValidator).to receive(:new).and_return(mock_sov)
              c2m.check_catalog_version
              expect(comp_moab.reload.status).to eq 'invalid_moab'
            end
          end

          it "invalid_moab changes to validity_unknown (due to newer version not checksum validated)" do
            comp_moab.invalid_moab!
            allow(mock_sov).to receive(:validation_errors).and_return(
              [{ Moab::StorageObjectValidator::MISSING_DIR => 'err msg' }]
            )
            allow(Stanford::StorageObjectValidator).to receive(:new).and_return(mock_sov)
            c2m.check_catalog_version
            expect(comp_moab.reload.status).to eq 'validity_unknown'
          end
        end

        context 'had INVALID_CHECKSUM_STATUS (which C2M cannot validate)' do
          before do
            allow(Stanford::StorageObjectValidator).to receive(:new).and_return(mock_sov)
            comp_moab.invalid_checksum!
          end

          it 'may have moab validation errors, but should still have INVALID_CHECKSUM_STATUS' do
            allow(mock_sov).to receive(:validation_errors).and_return(
              [{ Moab::StorageObjectValidator::MISSING_DIR => 'err msg' }]
            )
            c2m.check_catalog_version
            expect(comp_moab.reload.status).to eq 'invalid_checksum'
          end

          it 'would have no moab validation errors, but should still have INVALID_CHECKSUM_STATUS' do
            allow(mock_sov).to receive(:validation_errors).and_return([])
            c2m.check_catalog_version
            expect(comp_moab.reload.status).to eq 'invalid_checksum'
          end

          it 'has an AuditResults entry indicating inability to check the given status' do
            c2m.check_catalog_version
            expect(c2m.results.contains_result_code?(AuditResults::UNABLE_TO_CHECK_STATUS)).to eq true
          end
        end
      end
    end

    context 'catalog version > moab version' do
      before do
        moab = instance_double(Moab::StorageObject, size: 666, object_pathname: object_dir, current_version_id: 2, exist?: true)
        allow(Moab::StorageObject).to receive(:new).with(druid, instance_of(String)).and_return(moab)
      end

      it 'adds an UNEXPECTED_VERSION result' do
        c2m.instance_variable_set(:@results, results_double)
        expect(c2m.results).to receive(:add_result).with(
          AuditResults::UNEXPECTED_VERSION, db_obj_name: 'CompleteMoab', db_obj_version: comp_moab.version
        )
        c2m.check_catalog_version
      end

      it 'calls Stanford::StorageObjectValidator.validation_errors for moab' do
        expect(mock_sov).to receive(:validation_errors).and_return([])
        allow(Stanford::StorageObjectValidator).to receive(:new).and_return(mock_sov)
        c2m.check_catalog_version
      end

      it 'valid moab sets status to UNEXPECTED_VERSION_ON_STORAGE_STATUS' do
        orig = comp_moab.status
        c2m.check_catalog_version
        new_status = comp_moab.reload.status
        expect(new_status).not_to eq orig
        expect(new_status).to eq 'unexpected_version_on_storage'
      end

      context 'moab not found' do
        before do
          allow(mock_sov).to receive(:validation_errors).and_raise(Errno::ENOENT)
          allow(Stanford::StorageObjectValidator).to receive(:new).and_return(mock_sov)
        end

        it 'sets status to online_moab_not_found' do
          orig = comp_moab.status
          c2m.check_catalog_version
          new_status = comp_moab.reload.status
          expect(new_status).not_to eq orig
          expect(new_status).to eq 'online_moab_not_found'
        end

        it 'adds a MOAB_NOT_FOUND result' do
          c2m.instance_variable_set(:@results, results_double)
          expect(c2m.results).to receive(:add_result).with(AuditResults::MOAB_NOT_FOUND, anything)
          c2m.check_catalog_version
        end
      end

      context 'invalid moab' do
        before do
          allow(mock_sov).to receive(:validation_errors).and_return([foo: 'error message'])
          allow(Stanford::StorageObjectValidator).to receive(:new).and_return(mock_sov)
        end

        it 'sets status to INVALID_MOAB_STATUS' do
          orig = comp_moab.status
          c2m.check_catalog_version
          new_status = comp_moab.reload.status
          expect(new_status).not_to eq orig
          expect(new_status).to eq 'invalid_moab'
        end

        it 'adds an INVALID_MOAB result' do
          c2m.instance_variable_set(:@results, results_double)
          expect(c2m.results).to receive(:add_result).with(AuditResults::INVALID_MOAB, anything)
          c2m.check_catalog_version
        end
      end

      it 'adds a CM_STATUS_CHANGED result' do
        c2m.instance_variable_set(:@results, results_double)
        expect(c2m.results).to receive(:add_result).with(
          AuditResults::CM_STATUS_CHANGED, a_hash_including(:old_status, :new_status)
        )
        c2m.check_catalog_version
      end

      context 'check whether CompleteMoab already has a status other than OK_STATUS, re-check status if possible' do
        [
          'validity_unknown',
          'ok',
          'online_moab_not_found',
          'invalid_moab',
          'unexpected_version_on_storage'
        ].each do |orig_status|
          it "had #{orig_status}, should now have EXPECTED_VERS_NOT_FOUND_ON_STORAGE_STATUS" do
            comp_moab.status = orig_status
            comp_moab.save!
            allow(c2m).to receive(:moab_validation_errors).and_return([])
            c2m.check_catalog_version
            expect(comp_moab.reload.status).to eq 'unexpected_version_on_storage'
          end
        end

        [
          'validity_unknown',
          'ok',
          'online_moab_not_found',
          'invalid_moab',
          'unexpected_version_on_storage'
        ].each do |orig_status|
          it "had #{orig_status}, should now have INVALID_MOAB_STATUS" do
            comp_moab.status = orig_status
            comp_moab.save!
            allow(c2m).to receive(:moab_validation_errors).and_return(
              [{ Moab::StorageObjectValidator::MISSING_DIR => 'err msg' }]
            )
            c2m.check_catalog_version
            expect(comp_moab.reload.status).to eq 'invalid_moab'
          end
        end

        context 'had INVALID_CHECKSUM_STATUS, which C2M cannot validate' do
          before do
            allow(Stanford::StorageObjectValidator).to receive(:new).and_return(mock_sov)
            comp_moab.invalid_checksum!
          end

          it 'may have moab validation errors, but should still have INVALID_CHECKSUM_STATUS' do
            allow(mock_sov).to receive(:validation_errors).and_return(
              [{ Moab::StorageObjectValidator::MISSING_DIR => 'err msg' }]
            )
            c2m.check_catalog_version
            expect(comp_moab.reload.status).to eq 'invalid_checksum'
          end

          it 'would have no moab validation errors, but should still have INVALID_CHECKSUM_STATUS' do
            allow(mock_sov).to receive(:validation_errors).and_return([])
            c2m.check_catalog_version
            expect(comp_moab.reload.status).to eq 'invalid_checksum'
          end

          it 'has an AuditResults entry indicating inability to check the given status' do
            c2m.check_catalog_version
            expect(c2m.results.contains_result_code?(AuditResults::UNABLE_TO_CHECK_STATUS)).to eq true
          end
        end
      end
    end

    context 'moab found on disk' do
      # use the same setup as 'catalog version > moab version', since we know that should
      # lead to an update_status('unexpected_version_on_storage') call
      before do
        moab = instance_double(Moab::StorageObject, size: 666, object_pathname: object_dir, exist?: true)
        allow(Moab::StorageObject).to receive(:new).with(druid, instance_of(String)).and_return(moab)
        allow(moab).to receive(:current_version_id).and_return(2)
      end

      context 'DB transaction handling' do
        it 'on transaction failure, completes without raising error, removes CM_STATUS_CHANGED result code' do
          allow(comp_moab).to receive(:save!).and_raise(ActiveRecord::ConnectionTimeoutError)
          c2m.check_catalog_version
          expect(c2m.results.result_array).to include(a_hash_including(AuditResults::UNEXPECTED_VERSION))
          expect(c2m.results.result_array).not_to include(a_hash_including(AuditResults::CM_STATUS_CHANGED))
          expect(comp_moab.reload.status).not_to eq 'unexpected_version_on_storage'
        end
      end
    end
  end
end
