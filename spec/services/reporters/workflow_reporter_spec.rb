# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reporters::WorkflowReporter do
  let(:subject) { described_class.new }

  let(:client) { instance_double(Dor::Workflow::Client) }
  let(:druid) { 'ab123cd4567' }
  let(:actual_version) { 6 }
  let(:ms_root) { MoabStorageRoot.find_by(storage_location: 'spec/fixtures/storage_root01/sdr2objects') }
  let(:check_name) { 'FooCheck' }

  before do
    allow(Dor::Workflow::Client).to receive(:new).and_return(client)
    allow(Settings).to receive(:workflow_services_url).and_return('http://workflow')
    allow(client).to receive(:update_error_status)
    allow(client).to receive(:update_status)
  end

  describe '#report_errors' do
    context 'when INVALID_MOAB' do
      let(:result1) do
        {
          AuditResults::INVALID_MOAB =>
                            "Invalid Moab, validation errors: [Version directory name not in 'v00xx' format: original-v1]"
        }
      end
      let(:result2) do
        {
          AuditResults::INVALID_MOAB =>
                          "Invalid Moab, validation errors: [Version directory name not in 'v00xx' format: original-v2]"
        }
      end

      it 'updates workflow for each error' do
        subject.report_errors(druid: druid, version: actual_version, storage_area: ms_root, check_name: check_name, results: [result1, result2])
        error_msg1 = 'FooCheck (actual location: fixture_sr1; actual version: 6) || Invalid Moab, validation errors: ' \
          "[Version directory name not in 'v00xx' format: original-v1]"
        expect(client).to have_received(:update_error_status).with(druid: "druid:#{druid}",
                                                                   workflow: 'preservationAuditWF',
                                                                   process: 'moab-valid',
                                                                   error_msg: error_msg1)
        error_msg2 = 'FooCheck (actual location: fixture_sr1; actual version: 6) || Invalid Moab, validation errors: ' \
          "[Version directory name not in 'v00xx' format: original-v2]"
        expect(client).to have_received(:update_error_status).with(druid: "druid:#{druid}",
                                                                   workflow: 'preservationAuditWF',
                                                                   process: 'moab-valid',
                                                                   error_msg: error_msg2)
      end
    end

    context 'when other errors' do
      let(:result1) { { AuditResults::CM_PO_VERSION_MISMATCH => 'does not match PreservedObject current_version' } }
      let(:result2) { { AuditResults::UNEXPECTED_VERSION => 'actual version (6) has unexpected relationship to db version' } }

      it 'merges errors and updates workflow' do
        subject.report_errors(druid: druid, version: actual_version, storage_area: ms_root, check_name: check_name, results: [result1, result2])
        error_msg = 'FooCheck (actual location: fixture_sr1; actual version: 6) does not match PreservedObject current_version ' \
          '&& actual version (6) has unexpected relationship to db version'
        expect(client).to have_received(:update_error_status).with(druid: "druid:#{druid}",
                                                                   workflow: 'preservationAuditWF',
                                                                   process: 'preservation-audit',
                                                                   error_msg: error_msg)
      end
    end

    context 'when workflow does not exist' do
      let(:result) { { AuditResults::CM_PO_VERSION_MISMATCH => 'does not match PreservedObject current_version' } }

      before do
        call_count = 0
        allow(client).to receive(:update_error_status) do
          call_count += 1
          call_count == 1 ? raise(Dor::MissingWorkflowException) : nil
        end
        allow(client).to receive(:create_workflow_by_name)
      end

      it 'creates the workflow and retries' do
        subject.report_errors(druid: druid, version: actual_version, storage_area: ms_root, check_name: check_name, results: [result])
        error_msg = 'FooCheck (actual location: fixture_sr1; actual version: 6) does not match PreservedObject current_version'
        expect(client).to have_received(:update_error_status).with(druid: "druid:#{druid}",
                                                                   workflow: 'preservationAuditWF',
                                                                   process: 'preservation-audit',
                                                                   error_msg: error_msg).twice
        expect(client).to have_received(:create_workflow_by_name).with("druid:#{druid}", 'preservationAuditWF', version: 6)
      end
    end

    context 'when ignored error' do
      let(:result) { { AuditResults::ZIP_PARTS_NOT_CREATED => 'no zip_parts exist yet for this ZippedMoabVersion' } }

      it 'does not update workflow' do
        subject.report_errors(druid: druid, version: actual_version, storage_area: ms_root, check_name: check_name, results: [result])
        expect(client).not_to have_received(:update_error_status)
      end
    end
  end

  describe '#report_completed' do
    let(:result) { { AuditResults::CM_STATUS_CHANGED => 'CompleteMoab status changed from invalid_moab' } }

    it 'updates workflow' do
      subject.report_completed(druid: druid, version: actual_version, storage_area: ms_root, check_name: check_name, result: result)

      expect(client).to have_received(:update_status).with(druid: "druid:#{druid}",
                                                           workflow: 'preservationAuditWF',
                                                           process: 'preservation-audit',
                                                           status: 'completed')
      expect(client).to have_received(:update_status).with(druid: "druid:#{druid}",
                                                           workflow: 'preservationAuditWF',
                                                           process: 'moab-valid',
                                                           status: 'completed')
    end

    context 'when workflow does not exist' do
      before do
        call_count = 0
        allow(client).to receive(:update_status) do
          call_count += 1
          call_count == 1 ? raise(Dor::MissingWorkflowException) : nil
        end
        allow(client).to receive(:create_workflow_by_name)
      end

      it 'creates the workflow and retries' do
        subject.report_completed(druid: druid, version: actual_version, storage_area: ms_root, check_name: check_name, result: result)

        expect(client).to have_received(:update_status).with(druid: "druid:#{druid}",
                                                             workflow: 'preservationAuditWF',
                                                             process: 'preservation-audit',
                                                             status: 'completed').once
        expect(client).to have_received(:update_status).with(druid: "druid:#{druid}",
                                                             workflow: 'preservationAuditWF',
                                                             process: 'moab-valid',
                                                             status: 'completed').twice

        expect(client).to have_received(:create_workflow_by_name).with("druid:#{druid}", 'preservationAuditWF', version: 6)
      end
    end
  end
end
