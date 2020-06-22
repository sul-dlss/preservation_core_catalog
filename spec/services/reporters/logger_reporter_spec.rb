# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reporters::LoggerReporter do
  let(:subject) { described_class.new }

  let(:druid) { 'ab123cd4567' }
  let(:actual_version) { 6 }
  let(:ms_root) { MoabStorageRoot.find_by(storage_location: 'spec/fixtures/storage_root01/sdr2objects') }
  let(:check_name) { 'FooCheck' }

  before do
    # Force to find so that it is not logged within it block.
    ms_root
    allow(Rails.logger).to receive(:add)
  end

  describe '#report_errors' do
    let(:result1) { { AuditResults::CM_PO_VERSION_MISMATCH => version_not_matched_str } }
    let(:version_not_matched_str) { 'does not match PreservedObject current_version' }

    it 'logs to Rails logger' do
      subject.report_errors(druid: druid, version: actual_version, storage_area: ms_root, check_name: check_name, results: [result1])
      # Logs with check name, druid, storage root, and message
      expect(Rails.logger).to have_received(:add)
        .with(Logger::ERROR, 'FooCheck(ab123cd4567, fixture_sr1) does not match PreservedObject current_version')
    end

    context 'when multiple results' do
      let(:result2) { { AuditResults::ZIP_PARTS_NOT_CREATED => zip_parts_not_created_str } }
      let(:zip_parts_not_created_str) { 'no zip_parts exist yet for this ZippedMoabVersion' }

      it 'logs each result' do
        subject.report_errors(druid: druid, version: actual_version, storage_area: ms_root, check_name: check_name, results: [result1, result2])
        expect(Rails.logger).to have_received(:add).with(Logger::ERROR, a_string_matching(version_not_matched_str))
        expect(Rails.logger).to have_received(:add).with(Logger::WARN, a_string_matching(zip_parts_not_created_str))
      end
    end
  end

  describe '#report_completed' do
    let(:result) { { AuditResults::CM_STATUS_CHANGED => 'CompleteMoab status changed from invalid_moab' } }

    it 'logs to Rails logger' do
      subject.report_completed(druid: druid, version: actual_version, storage_area: ms_root, check_name: check_name, result: result)
      expect(Rails.logger).to have_received(:add)
        .with(Logger::INFO, 'FooCheck(ab123cd4567, fixture_sr1) CompleteMoab status changed from invalid_moab')
    end
  end

  describe '.logger_severity_level' do
    it 'CM_PO_VERSION_MISMATCH is an ERROR' do
      expect(subject.send(:logger_severity_level, AuditResults::CM_PO_VERSION_MISMATCH)).to eq Logger::ERROR
    end

    it 'DB_OBJ_DOES_NOT_EXIST is WARN' do
      expect(subject.send(:logger_severity_level, AuditResults::DB_OBJ_DOES_NOT_EXIST)).to eq Logger::WARN
    end

    it 'CREATED_NEW_OBJECT is INFO' do
      expect(subject.send(:logger_severity_level, AuditResults::CREATED_NEW_OBJECT)).to eq Logger::INFO
    end

    it 'default for unrecognized value is ERROR' do
      expect(subject.send(:logger_severity_level, :whatever)).to eq Logger::ERROR
    end
  end
end
