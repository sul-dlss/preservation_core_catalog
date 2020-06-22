# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Audit::CatalogToArchive do
  let(:zmv) { create(:zipped_moab_version) }
  let(:results) { AuditResults.new(zmv.preserved_object.druid, nil, zmv.zip_endpoint, 'CatalogToArchiveSpec') }
  let(:version) { zmv.version }
  let(:endpoint_name) { zmv.zip_endpoint.endpoint_name }
  let(:result_prefix) { "#{version} on #{endpoint_name}" }

  context 'zip parts have not been created yet' do
    it 'logs an error indicating that zip parts have not beeen created yet' do
      described_class.check_child_zip_part_attributes(zmv, results)
      expect(results.result_array).to include(
        a_hash_including(
          AuditResults::ZIP_PARTS_NOT_CREATED => "#{result_prefix}: no zip_parts exist yet for this ZippedMoabVersion"
        )
      )
    end

    it 'returns false' do
      expect(described_class.check_child_zip_part_attributes(zmv, results)).to be(false)
    end
  end

  context 'different parts have different expected parts_count values' do
    before do
      args = attributes_for(:zip_part)
      zmv.zip_parts.create!(
        [
          args.merge(status: 'ok', parts_count: 2, suffix: '.zip'),
          args.merge(status: 'ok', parts_count: 2, suffix: '.z01'),
          args.merge(status: 'ok', parts_count: 3, suffix: '.z02')
        ]
      )
    end

    it 'logs the discrepancy' do
      described_class.check_child_zip_part_attributes(zmv, results)
      child_parts_counts = zmv.child_parts_counts
      exp_err_msg = "#{result_prefix}: ZippedMoabVersion has variation in child parts_counts: #{child_parts_counts}"
      expect(results.result_array).to include(
        a_hash_including(AuditResults::ZIP_PARTS_COUNT_INCONSISTENCY => exp_err_msg)
      )
    end
  end

  context 'parts_count is consistent across parts and with the actual number of zip parts' do
    before do
      args = attributes_for(:zip_part)
      zmv.zip_parts.create!(
        [
          args.merge(status: 'ok', parts_count: 3, suffix: '.zip'),
          args.merge(status: 'ok', parts_count: 3, suffix: '.z01'),
          args.merge(status: 'ok', parts_count: 3, suffix: '.z02')
        ]
      )
    end

    it "doesn't log parts_count errors" do
      described_class.check_child_zip_part_attributes(zmv, results)
      expect(results.result_array).not_to include(a_hash_including(AuditResults::ZIP_PARTS_COUNT_INCONSISTENCY))
    end

    it "doesn't log an error about parts_count mismatching number of zip_parts" do
      described_class.check_child_zip_part_attributes(zmv, results)
      expect(results.result_array).not_to include(a_hash_including(AuditResults::ZIP_PARTS_COUNT_DIFFERS_FROM_ACTUAL))
    end
  end

  context "parts_count is consistent across parts, but doesn't match the actual number of child parts" do
    before do
      args = attributes_for(:zip_part)
      zmv.zip_parts.create!(
        [
          args.merge(status: 'ok', parts_count: 3, suffix: '.zip'),
          args.merge(status: 'ok', parts_count: 3, suffix: '.z01')
        ]
      )
    end

    it 'logs the discrepancy' do
      described_class.check_child_zip_part_attributes(zmv, results)
      msg = "#{result_prefix}: ZippedMoabVersion stated parts count"\
        " (3) doesn't match actual number of zip parts rows (2)"
      expect(results.result_array).to include(
        a_hash_including(AuditResults::ZIP_PARTS_COUNT_DIFFERS_FROM_ACTUAL => msg)
      )
    end
  end

  context 'zip parts have been created' do
    context 'some parts are unreplicated' do
      before do
        args = attributes_for(:zip_part)
        zmv.zip_parts.create!(
          [
            args.merge(status: 'unreplicated', parts_count: 3, suffix: '.zip'),
            args.merge(status: 'ok', parts_count: 3, suffix: '.z01'),
            args.merge(status: 'unreplicated', parts_count: 3, suffix: '.z02')
          ]
        )
      end

      it 'logs the unreplicated parts' do
        unreplicated_parts = zmv.zip_parts.where(suffix: ['.zip', '.z02'])
        msg = "#{result_prefix}: not all ZippedMoabVersion parts are replicated yet: #{unreplicated_parts.to_a}"
        described_class.check_child_zip_part_attributes(zmv, results)
        expect(results.result_array).to include(a_hash_including(AuditResults::ZIP_PARTS_NOT_ALL_REPLICATED => msg))
      end

      it 'returns true' do
        expect(described_class.check_child_zip_part_attributes(zmv, results)).to be(true)
      end
    end
  end
end
