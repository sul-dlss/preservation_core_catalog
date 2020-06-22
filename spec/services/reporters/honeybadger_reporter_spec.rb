# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reporters::HoneybadgerReporter do
  let(:subject) { described_class.new }

  let(:druid) { 'ab123cd4567' }
  let(:actual_version) { 6 }
  let(:ms_root) { MoabStorageRoot.find_by(storage_location: 'spec/fixtures/storage_root01/sdr2objects') }
  let(:check_name) { 'FooCheck' }

  before do
    allow(Honeybadger).to receive(:notify)
  end

  describe '#report_errors' do
    context 'when handled error' do
      let(:result1) { { AuditResults::MOAB_NOT_FOUND => 'db CompleteMoab exists but Moab not found' } }
      let(:result2) { { AuditResults::ZIP_PART_NOT_FOUND => 'replicated part not found' } }

      it 'notifies for each error' do
        subject.report_errors(druid: druid, version: actual_version, storage_area: ms_root, check_name: check_name, results: [result1, result2])
        expect(Honeybadger).to have_received(:notify).with('FooCheck(druid:ab123cd4567, fixture_sr1) db CompleteMoab exists but Moab not found')
        expect(Honeybadger).to have_received(:notify).with('FooCheck(druid:ab123cd4567, fixture_sr1) replicated part not found')
      end
    end

    context 'when ignored error' do
      let(:result) { { AuditResults::ZIP_PARTS_NOT_CREATED => 'no zip_parts exist yet for this ZippedMoabVersion' } }

      it 'does not notify' do
        subject.report_errors(druid: druid, version: actual_version, storage_area: ms_root, check_name: check_name, results: [result])
        expect(Honeybadger).not_to have_received(:notify)
      end
    end
  end

  describe '#report_completed' do
    let(:result) { { AuditResults::CM_STATUS_CHANGED => 'CompleteMoab status changed from invalid_moab' } }

    it 'does not notify' do
      subject.report_completed(druid: druid, version: actual_version, storage_area: ms_root, check_name: check_name, result: result)
      expect(Honeybadger).not_to have_received(:notify)
    end
  end
end
