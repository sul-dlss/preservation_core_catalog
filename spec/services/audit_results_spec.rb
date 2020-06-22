# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditResults do
  let(:actual_version) { 6 }
  let(:audit_results) { described_class.new(druid, actual_version, ms_root) }
  let(:druid) { 'ab123cd4567' }
  let(:events_client) { instance_double(Dor::Services::Client::Events) }
  let(:ms_root) { MoabStorageRoot.find_by(storage_location: 'spec/fixtures/storage_root01/sdr2objects') }

  describe '#new' do
    it 'sets result_array attr to []' do
      expect(audit_results.result_array).to eq []
    end

    it 'sets druid attr to arg' do
      expect(audit_results.druid).to eq druid
    end

    it 'sets actual_version attr to arg' do
      expect(audit_results.actual_version).to eq actual_version
    end
  end

  describe '#report_results' do
    let(:workflow_reporter) { instance_double(Reporters::WorkflowReporter, report_errors: nil, report_completed: nil) }
    let(:event_service_reporter) { instance_double(Reporters::EventServiceReporter, report_errors: nil, report_completed: nil) }
    let(:honeybadger_reporter) { instance_double(Reporters::HoneybadgerReporter, report_errors: nil, report_completed: nil) }
    let(:logger_reporter) { instance_double(Reporters::LoggerReporter, report_errors: nil, report_completed: nil) }

    before do
      allow(Reporters::WorkflowReporter).to receive(:new).and_return(workflow_reporter)
      allow(Reporters::EventServiceReporter).to receive(:new).and_return(event_service_reporter)
      allow(Reporters::HoneybadgerReporter).to receive(:new).and_return(honeybadger_reporter)
      allow(Reporters::LoggerReporter).to receive(:new).and_return(logger_reporter)

      audit_results.add_result(AuditResults::INVALID_MOAB, [
                                 "Version directory name not in 'v00xx' format: original-v1",
                                 'Version v0005: No files present in manifest dir'
                               ])
      audit_results.add_result(AuditResults::CM_STATUS_CHANGED, old_status: 'invalid_checksum', new_status: 'ok')
    end

    it 'invokes the reporters' do
      audit_results.report_results
      expect(workflow_reporter).to have_received(:report_errors)
        .with(druid: druid, version: actual_version, storage_area: ms_root, check_name: nil,
              results: [{ invalid_moab: "Invalid Moab, validation errors: [\"Version directory name not in 'v00xx' " \
          'format: original-v1", "Version v0005: No files present in manifest dir"]' }])
      expect(event_service_reporter).to have_received(:report_errors)
        .with(druid: druid, version: actual_version, storage_area: ms_root, check_name: nil,
              results: [{ invalid_moab: "Invalid Moab, validation errors: [\"Version directory name not in 'v00xx' " \
          'format: original-v1", "Version v0005: No files present in manifest dir"]' }])
      expect(honeybadger_reporter).to have_received(:report_errors)
        .with(druid: druid, version: actual_version, storage_area: ms_root, check_name: nil,
              results: [{ invalid_moab: "Invalid Moab, validation errors: [\"Version directory name not in 'v00xx' " \
          'format: original-v1", "Version v0005: No files present in manifest dir"]' }])
      expect(logger_reporter).to have_received(:report_errors)
        .with(druid: druid, version: actual_version, storage_area: ms_root, check_name: nil,
              results: [{ invalid_moab: "Invalid Moab, validation errors: [\"Version directory name not in 'v00xx' " \
          'format: original-v1", "Version v0005: No files present in manifest dir"]' }])

      expect(workflow_reporter).to have_received(:report_completed)
        .with(druid: druid, version: actual_version, storage_area: ms_root, check_name: nil,
              result: { cm_status_changed: 'CompleteMoab status changed from invalid_checksum to ok' })
      expect(event_service_reporter).to have_received(:report_completed)
        .with(druid: druid, version: actual_version, storage_area: ms_root, check_name: nil,
              result: { cm_status_changed: 'CompleteMoab status changed from invalid_checksum to ok' })
      expect(honeybadger_reporter).to have_received(:report_completed)
        .with(druid: druid, version: actual_version, storage_area: ms_root, check_name: nil,
              result: { cm_status_changed: 'CompleteMoab status changed from invalid_checksum to ok' })
      expect(logger_reporter).to have_received(:report_completed)
        .with(druid: druid, version: actual_version, storage_area: ms_root, check_name: nil,
              result: { cm_status_changed: 'CompleteMoab status changed from invalid_checksum to ok' })
    end
  end

  describe '#add_result' do
    it 'adds a hash entry to the result_array' do
      expect(audit_results.result_array.size).to eq 0
      code = AuditResults::CM_PO_VERSION_MISMATCH
      addl_hash = { cm_version: 1, po_version: 2 }
      audit_results.add_result(code, addl_hash)
      expect(audit_results.result_array.size).to eq 1
      exp_msg = AuditResults::RESPONSE_CODE_TO_MESSAGES[code] % addl_hash
      expect(audit_results.result_array.first).to eq code => exp_msg
    end

    it 'can take a single result code argument' do
      # see above
    end

    it 'can take a second msg_args argument' do
      code = AuditResults::VERSION_MATCHES
      audit_results.add_result(code, 'foo')
      expect(audit_results.result_array.size).to eq 1
      expect(audit_results.result_array.first).to eq code => 'actual version (6) matches foo db version'
    end
  end

  describe '#remove_db_updated_results' do
    before do
      code = AuditResults::CM_PO_VERSION_MISMATCH
      result_msg_args = { cm_version: 1, po_version: 2 }
      audit_results.add_result(code, result_msg_args)
      code = AuditResults::CM_STATUS_CHANGED
      result_msg_args = { old_status: 'ok', new_status: 'invalid_moab' }
      audit_results.add_result(code, result_msg_args)
      code = AuditResults::CREATED_NEW_OBJECT
      audit_results.add_result(code)
      code = AuditResults::INVALID_MOAB
      audit_results.add_result(code, 'foo')
    end

    it 'removes results matching DB_UPDATED_CODES' do
      expect(audit_results.result_array.size).to eq 4
      audit_results.remove_db_updated_results
      expect(audit_results.result_array.size).to eq 2
      audit_results.result_array.each do |result_hash|
        expect(AuditResults::DB_UPDATED_CODES).not_to include(result_hash.keys.first)
      end
      expect(audit_results.result_array).not_to include(a_hash_including(AuditResults::CREATED_NEW_OBJECT))
      expect(audit_results.result_array).not_to include(a_hash_including(AuditResults::CM_STATUS_CHANGED))
    end

    it 'keeps results not matching DB_UPDATED_CODES' do
      audit_results.remove_db_updated_results
      expect(audit_results.result_array).to include(a_hash_including(AuditResults::CM_PO_VERSION_MISMATCH))
      expect(audit_results.result_array).to include(a_hash_including(AuditResults::INVALID_MOAB))
    end
  end

  describe '#contains_result_code?' do
    it 'returns true if the result code is there, false if not' do
      expect(audit_results.result_array.size).to eq 0
      added_code = AuditResults::CM_PO_VERSION_MISMATCH
      other_code = AuditResults::VERSION_MATCHES
      audit_results.add_result(added_code, cm_version: 1, po_version: 2)
      expect(audit_results.contains_result_code?(added_code)).to eq true
      expect(audit_results.contains_result_code?(other_code)).to eq false
    end
  end

  describe '#status_changed_to_ok?' do
    it 'returns true if the new status is ok' do
      added_code = AuditResults::CM_STATUS_CHANGED
      audit_results.add_result(added_code, old_status: 'invalid_checksum', new_status: 'ok')
      expect(audit_results.status_changed_to_ok?(audit_results.result_array.first)).to eq true
    end

    it 'returns false if the new status is not ok' do
      added_code = AuditResults::CM_STATUS_CHANGED
      audit_results.add_result(added_code, old_status: 'invalid_checksum', new_status: 'invalid_moab')
      expect(audit_results.status_changed_to_ok?(audit_results.result_array.first)).to eq false
    end
  end

  describe '#to_json' do
    it 'returns valid JSON for the current result_array' do
      audit_results.add_result(AuditResults::CM_PO_VERSION_MISMATCH, cm_version: 1, po_version: 2)
      json_text = audit_results.to_json
      json_parsed = JSON.parse(json_text)

      exp_msg = 'CompleteMoab online Moab version 1 does not match PreservedObject current_version 2'
      expect(json_parsed.length).to eq 2
      expect(json_parsed['result_array'].first.length).to eq 1
      expect(json_parsed['result_array'].first.keys).to eq [AuditResults::CM_PO_VERSION_MISMATCH.to_s]
      expect(json_parsed['result_array'].first[AuditResults::CM_PO_VERSION_MISMATCH.to_s]).to eq exp_msg
      expect(json_parsed['druid']).to eq druid
    end
  end
end
