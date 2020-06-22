# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ZippedMoabVersion, type: :model do
  let(:preserved_object) { create(:preserved_object) }
  let(:zmv) { create(:zipped_moab_version, preserved_object: preserved_object) }

  it 'is not valid without all required valid attributes' do
    expect(described_class.new).not_to be_valid
    expect(described_class.new(preserved_object: preserved_object)).not_to be_valid
    expect(zmv).to be_valid
  end

  it { is_expected.to validate_presence_of(:zip_endpoint) }
  it { is_expected.to validate_presence_of(:preserved_object) }
  it { is_expected.to validate_presence_of(:version) }

  it { is_expected.to belong_to(:preserved_object) }
  it { is_expected.to belong_to(:zip_endpoint) }
  it { is_expected.to have_db_index(:zip_endpoint_id) }
  it { is_expected.to have_many(:zip_parts) }
  it { is_expected.to have_db_index(:preserved_object_id) }

  describe '#replicate!' do
    before { zmv.save! }

    it 'if PreservedObject does not have a replicatable moab, returns false, does not enqueue' do
      expect(preserved_object).to receive(:moab_replication_storage_location).and_return(nil)
      expect(ZipmakerJob).not_to receive(:perform_later)
      expect(zmv.replicate!).to be(nil)
    end

    it 'if PreservedObject is replicatable, passes druid and version to Zipmaker' do
      expect(preserved_object).to receive(:moab_replication_storage_location).and_return('/storage_root/bc123df4567')
      expect(ZipmakerJob).to receive(:perform_later).with(preserved_object.druid, zmv.version, '/storage_root/bc123df4567')
      zmv.replicate!
    end
  end

  describe '.by_druid' do
    before { zmv.save! }

    let(:po_diff) { build(:preserved_object, druid: 'jj925bx9565') }
    let!(:zmv_diff_druid) { create(:zipped_moab_version, preserved_object: po_diff) }

    it "returns the ZMV's for the given druid" do
      expect(described_class.by_druid('jj925bx9565').sort).to include zmv_diff_druid
      expect(described_class.by_druid('jj925bx9565').sort).not_to include zmv
    end
  end

  describe '#child_parts_counts' do
    context 'there are no parts' do
      it 'returns an empty list' do
        expect(zmv.child_parts_counts).to eq([])
      end
    end

    context 'there is one part' do
      before do
        args = attributes_for(:zip_part)
        zmv.zip_parts.create!([args.merge(status: 'ok', parts_count: 1, suffix: '.zip')])
      end

      it 'returns a single row with a count of 1 for 1 part' do
        expect(zmv.child_parts_counts).to eq([[1, 1]])
      end
    end

    context 'there are multiple parts, all with the same count' do
      before do
        args = attributes_for(:zip_part)
        zmv.zip_parts.create!(
          [
            args.merge(status: 'ok', parts_count: 4, suffix: '.zip'),
            args.merge(status: 'ok', parts_count: 4, suffix: '.z01'),
            args.merge(status: 'ok', parts_count: 4, suffix: '.z02'),
            args.merge(status: 'ok', parts_count: 4, suffix: '.z03')
          ]
        )
      end

      it 'returns a single row with the parts_count for the number of parts' do
        expect(zmv.child_parts_counts).to eq([[4, 4]])
      end
    end

    context 'there are multiple parts, some with differing counts' do
      before do
        args = attributes_for(:zip_part)
        zmv.zip_parts.create!(
          [
            args.merge(status: 'ok', parts_count: 3, suffix: '.zip'),
            args.merge(status: 'ok', parts_count: 3, suffix: '.z01'),
            args.merge(status: 'ok', parts_count: 3, suffix: '.z02'),
            args.merge(status: 'ok', parts_count: 4, suffix: '.z03')
          ]
        )
      end

      it 'returns a row for each distinct parts_count, each with the number of parts that claim that count' do
        expect(zmv.child_parts_counts.sort).to eq([[3, 3], [4, 1]])
      end
    end
  end

  describe '#all_parts_replicated?' do
    context 'there are no parts' do
      it 'returns false' do
        expect(zmv.all_parts_replicated?).to be(false)
      end
    end

    context 'there are multiple parts, but not all are ok' do
      before do
        args = attributes_for(:zip_part)
        zmv.zip_parts.create!(
          [
            args.merge(status: 'ok', parts_count: 3, suffix: '.zip'),
            args.merge(status: 'unreplicated', parts_count: 3, suffix: '.z01'),
            args.merge(status: 'ok', parts_count: 3, suffix: '.z02')
          ]
        )
      end

      it 'returns false' do
        expect(zmv.all_parts_replicated?).to be(false)
      end
    end

    context 'there are multiple parts, and all are ok' do
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

      it 'returns true' do
        expect(zmv.all_parts_replicated?).to be(true)
      end
    end
  end
end
