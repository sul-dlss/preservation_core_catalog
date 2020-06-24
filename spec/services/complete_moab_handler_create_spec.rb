# frozen_string_literal: true

require 'rails_helper'
require 'services/shared_examples_complete_moab_handler'

RSpec.describe CompleteMoabHandler do
  let(:druid) { 'ab123cd4567' }
  let(:incoming_version) { 6 }
  let(:incoming_size) { 9876 }
  let(:storage_dir) { 'spec/fixtures/storage_root01/sdr2objects' }
  let(:ms_root) { MoabStorageRoot.find_by(storage_location: storage_dir) }
  let(:complete_moab_handler) { described_class.new(druid, incoming_version, incoming_size, ms_root) }
  let(:exp_msg) { 'added object to db as it did not exist' }
  let(:workflow_reporter) { instance_double(Reporters::WorkflowReporter, report_errors: nil) }
  let(:logger_reporter) { instance_double(Reporters::LoggerReporter, report_errors: nil) }
  let(:honeybadger_reporter) { instance_double(Reporters::HoneybadgerReporter, report_errors: nil) }
  let(:event_service_reporter) { instance_double(Reporters::EventServiceReporter, report_errors: nil) }

  before do
    allow(Reporters::WorkflowReporter).to receive(:new).and_return(workflow_reporter)
    allow(Reporters::LoggerReporter).to receive(:new).and_return(logger_reporter)
    allow(Reporters::HoneybadgerReporter).to receive(:new).and_return(honeybadger_reporter)
    allow(Reporters::EventServiceReporter).to receive(:new).and_return(event_service_reporter)
  end

  describe '#create' do
    it 'creates PreservedObject and CompleteMoab and PreservedObjectsPrimaryMoab in database' do
      complete_moab_handler.create
      new_po = PreservedObject.find_by(druid: druid)
      new_cm = new_po.complete_moabs.find_by(version: incoming_version)
      expect(new_po.current_version).to eq incoming_version
      expect(new_cm.moab_storage_root).to eq ms_root
      expect(new_cm.size).to eq incoming_size
      expect(new_po.preserved_objects_primary_moab.complete_moab_id).to eq new_cm.id
    end

    it 'creates the CompleteMoab with "ok" status and validation timestamps if caller ran CV' do
      complete_moab_handler.create(true)
      new_cm = complete_moab_handler.pres_object.complete_moabs.find_by(version: incoming_version)
      expect(new_cm.status).to eq 'ok'
      expect(new_cm.last_version_audit).to be_a ActiveSupport::TimeWithZone
      expect(new_cm.last_moab_validation).to be_a ActiveSupport::TimeWithZone
      expect(new_cm.last_checksum_validation).to be_a ActiveSupport::TimeWithZone
    end

    it_behaves_like 'attributes validated', :create

    it 'object already exists' do
      complete_moab_handler.create
      new_complete_moab_handler = described_class.new(druid, incoming_version, incoming_size, ms_root)
      results = new_complete_moab_handler.create
      code = AuditResults::DB_OBJ_ALREADY_EXISTS
      expect(results).to include(a_hash_including(code => a_string_matching('CompleteMoab db object already exists')))
    end

    context 'a moab (for the same druid) on a different storage root already exists' do
      before do
        po = create(:preserved_object, druid: druid)
        other_storage_root = create(:moab_storage_root)
        create(:complete_moab, preserved_object: po, moab_storage_root: other_storage_root)
      end

      it 'creates the new CompleteMoab in database' do
        complete_moab_handler.create
        existing_po = PreservedObject.find_by(druid: druid)
        new_cm = existing_po.complete_moabs.find_by(moab_storage_root: ms_root)
        expect(existing_po.current_version).to eq incoming_version
        expect(new_cm.version).to eq incoming_version
        expect(new_cm.size).to eq incoming_size
      end
    end

    it_behaves_like 'calls AuditResults.report_results', :create

    context 'db update error' do
      context 'ActiveRecordError' do
        before do
          allow(PreservedObject).to receive(:create!).with(hash_including(druid: druid))
                                                     .and_raise(ActiveRecord::ActiveRecordError, 'foo')
        end

        it 'DB_UPDATE_FAILED result' do
          expect(complete_moab_handler.create).to include(a_hash_including(AuditResults::DB_UPDATE_FAILED))
        end

        it 'does NOT get CREATED_NEW_OBJECT result' do
          expect(complete_moab_handler.create).not_to include(hash_including(AuditResults::CREATED_NEW_OBJECT))
        end
      end

      it "rolls back PreservedObject creation if the CompleteMoab can't be created (e.g. due to DB constraint violation)" do
        po = instance_double(PreservedObject, complete_moabs: instance_double(ActiveRecord::Relation))
        allow(PreservedObject).to receive(:create!).with(hash_including(druid: druid)).and_return(po)
        allow(po.complete_moabs).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
        complete_moab_handler.create
        expect(PreservedObject.find_by(druid: druid)).to be_nil
      end
    end

    context 'returns' do
      let(:result) { complete_moab_handler.create }

      it '1 result of CREATED_NEW_OBJECT' do
        expect(result).to be_an_instance_of Array
        expect(result.size).to eq 1
        expect(result.first).to match(a_hash_including(AuditResults::CREATED_NEW_OBJECT => exp_msg))
      end
    end
  end

  describe '#create_after_validation' do
    let(:valid_druid) { 'bp628nk4868' }
    let(:storage_dir) { 'spec/fixtures/storage_root02/sdr2objects' }
    let(:complete_moab_handler) { described_class.new(valid_druid, incoming_version, incoming_size, ms_root) }

    it_behaves_like 'attributes validated', :create_after_validation

    it_behaves_like 'calls AuditResults.report_results', :create_after_validation

    context 'sets validation timestamps' do
      let(:t) { Time.current }
      let(:ms_root) { MoabStorageRoot.find_by(storage_location: storage_dir) }
      let(:cm_db_obj) { complete_moab_handler.pres_object.complete_moabs.first! }

      before { complete_moab_handler.create_after_validation }

      it 'sets last_moab_validation with current time' do
        expect(cm_db_obj.last_moab_validation).to be_within(10).of(t)
      end

      it 'sets last_version_audit with current time' do
        expect(cm_db_obj.last_version_audit).to be_within(10).of(t)
      end
    end

    it 'creates PreservedObject and CompleteMoab and PreservedObjectsPrimaryMoab in database when there are no validation errors' do
      complete_moab_handler = described_class.new(valid_druid, incoming_version, incoming_size, ms_root)
      complete_moab_handler.create_after_validation
      new_po = PreservedObject.find_by(druid: valid_druid, current_version: incoming_version)
      expect(new_po).not_to be_nil
      new_cm = new_po.complete_moabs.find_by(moab_storage_root: ms_root, version: incoming_version)
      expect(new_cm).not_to be_nil
      expect(new_cm.status).to eq 'validity_unknown'
      expect(new_po.preserved_objects_primary_moab.complete_moab_id).to eq new_cm.id
    end

    it 'creates CompleteMoab with "ok" status and validation timestamps if no validation errors and caller ran CV' do
      complete_moab_handler = described_class.new(valid_druid, incoming_version, incoming_size, ms_root)
      complete_moab_handler.create_after_validation(true)
      new_po = PreservedObject.find_by(druid: valid_druid, current_version: incoming_version)
      expect(new_po).not_to be_nil
      new_cm = new_po.complete_moabs.find_by(moab_storage_root: ms_root, version: incoming_version)
      expect(new_cm).not_to be_nil
      expect(new_cm.status).to eq 'ok'
      expect(new_cm.last_checksum_validation).to be_an ActiveSupport::TimeWithZone
    end

    it 'calls moab-versioning Stanford::StorageObjectValidator.validation_errors' do
      mock_sov = instance_double(Stanford::StorageObjectValidator)
      expect(mock_sov).to receive(:validation_errors).and_return([])
      allow(Stanford::StorageObjectValidator).to receive(:new).and_return(mock_sov)
      complete_moab_handler = described_class.new(valid_druid, incoming_version, incoming_size, ms_root)
      complete_moab_handler.create_after_validation
    end

    context 'when moab is invalid' do
      let(:storage_dir) { 'spec/fixtures/bad_root01/bad_moab_storage_trunk' }
      let(:ms_root) { MoabStorageRoot.find_by(storage_location: storage_dir) }
      let(:invalid_druid) { 'xx000xx0000' }
      let(:complete_moab_handler) { described_class.new(invalid_druid, incoming_version, incoming_size, ms_root) }

      # add storage root with invalid moab to the MoabStorageRoots table
      before do
        MoabStorageRoot.find_or_create_by!(name: 'bad_fixture_dir') do |ms_root|
          ms_root.storage_location = storage_dir
        end
      end

      it 'creates PreservedObject, and CompleteMoab with "invalid_moab" status, and PreservedObjectsPrimaryMoab in database' do
        complete_moab_handler.create_after_validation
        new_po = PreservedObject.find_by(druid: invalid_druid, current_version: incoming_version)
        expect(new_po).not_to be_nil
        new_cm = new_po.complete_moabs.find_by(moab_storage_root: ms_root, version: incoming_version)
        expect(new_cm).not_to be_nil
        expect(new_cm.status).to eq 'invalid_moab'
        expect(new_cm.last_moab_validation).to be_a ActiveSupport::TimeWithZone
        expect(new_cm.last_version_audit).to be_a ActiveSupport::TimeWithZone
        expect(new_po.preserved_objects_primary_moab.complete_moab_id).to eq new_cm.id
      end

      it 'creates CompleteMoab with "invalid_moab" status in database even if caller ran CV' do
        complete_moab_handler.create_after_validation(true)
        new_po = PreservedObject.find_by(druid: invalid_druid, current_version: incoming_version)
        expect(new_po).not_to be_nil
        new_cm = new_po.complete_moabs.find_by(moab_storage_root: ms_root, version: incoming_version)
        expect(new_cm).not_to be_nil
        expect(new_cm.status).to eq 'invalid_moab'
      end

      it 'includes invalid moab result' do
        results = complete_moab_handler.create_after_validation
        expect(results).to include(a_hash_including(AuditResults::INVALID_MOAB => /Invalid Moab, validation errors:/))
      end

      context 'db update error' do
        context 'ActiveRecordError' do
          let(:results) do
            allow(PreservedObject).to receive(:create!).with(hash_including(druid: invalid_druid))
                                                       .and_raise(ActiveRecord::ActiveRecordError, 'foo')
            complete_moab_handler = described_class.new(invalid_druid, incoming_version, incoming_size, ms_root)
            complete_moab_handler.create_after_validation
          end

          it 'DB_UPDATE_FAILED result' do
            expect(results).to include(a_hash_including(AuditResults::DB_UPDATE_FAILED))
          end

          it 'does NOT get CREATED_NEW_OBJECT result' do
            expect(results).not_to include(hash_including(AuditResults::CREATED_NEW_OBJECT))
          end
        end

        it "rolls back PreservedObject creation if the CompleteMoab can't be created (e.g. due to DB constraint violation)" do
          allow(CompleteMoab).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
          complete_moab_handler = described_class.new(invalid_druid, incoming_version, incoming_size, ms_root)
          complete_moab_handler.create
          expect(PreservedObject.where(druid: druid)).not_to exist
        end
      end
    end

    context 'returns' do
      let(:result) { complete_moab_handler.create_after_validation }

      it '1 CREATED_NEW_OBJECT result' do
        expect(result).to be_an_instance_of Array
        expect(result.size).to eq 1
        expect(result.first).to include(AuditResults::CREATED_NEW_OBJECT => exp_msg)
      end
    end
  end
end
