# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Audit::MoabToCatalog do
  let(:storage_dir) { 'spec/fixtures/storage_root01/sdr2objects' }
  let(:ms_root) { MoabStorageRoot.find_by!(storage_location: storage_dir) }
  let(:moab) do
    m = instance_double(Moab::StorageObject, object_pathname: storage_dir, :storage_root= => nil)
    allow(Moab::StorageObject).to receive(:new).and_return(m)
    m
  end

  before do
    allow(described_class.logger).to receive(:info) # silence STDOUT chatter
    allow(WorkflowReporter).to receive(:report_error)
  end

  describe '.logger' do
    let(:logfile) { Rails.root.join('log', 'm2c.log') }

    after { FileUtils.rm_f(logfile) }

    it 'writes to STDOUT and its own log' do
      expect { described_class.logger.debug("foobar") }.to output(/foobar/).to_stdout_from_any_process
      expect(File).to exist(logfile)
    end
  end

  describe ".seed_catalog_for_all_storage_roots" do
    it 'calls seed_catalog_for_dir with the right argument once per root' do
      expect(described_class).to receive(:seed_catalog_for_dir).exactly(MoabStorageRoot.count).times
      MoabStorageRoot.pluck(:storage_location) do |path|
        expect(described_class).to receive(:seed_catalog_for_dir).with("#{path}/#{Settings.moab.storage_trunk}")
      end
      described_class.seed_catalog_for_all_storage_roots
    end
  end

  describe '.check_existence_for_druid' do
    let(:druid) { 'bz514sm9647' }
    let(:results) do
      [{ db_obj_does_not_exist: "#<ActiveRecord::RecordNotFound: Couldn't find PreservedObject> db object does not exist" },
       { created_new_object: "added object to db as it did not exist" }]
    end

    it 'finds the relevant moab' do
      expect(Stanford::StorageServices).to receive(:find_storage_object).with(druid).and_call_original
      described_class.check_existence_for_druid(druid)
    end

    it 'finds the correct MoabStorageRoot' do
      expect(MoabStorageRoot).to receive(:find_by!).with(storage_location: storage_dir)
      described_class.check_existence_for_druid(druid)
    end

    it 'calls pohandler.check_existence' do
      po_handler = instance_double('PreservedObjectHandler')
      expect(PreservedObjectHandler).to receive(:new).with(
        druid,
        3, # current_version
        instance_of(Integer), # size
        ms_root
      ).and_return(po_handler)
      expect(po_handler).to receive(:logger=)
      expect(po_handler).to receive(:check_existence)
      described_class.check_existence_for_druid(druid)
    end

    it 'returns results' do
      expect(described_class.check_existence_for_druid(druid)).to eq results
    end

    context 'given a druid that does not exist' do
      let(:druid) { 'db102hs2345' }

      it 'does not call pohandler.check_existence' do
        expect(PreservedObjectHandler).not_to receive(:new)
        described_class.check_existence_for_druid(druid)
      end
    end
  end

  describe '.check_existence_for_druid_list' do
    it 'calls MoabToCatalog.check_existence_for_druid once per druid' do
      csv_file_path = 'spec/fixtures/druid_list.csv'
      CSV.foreach(csv_file_path) do |row|
        expect(described_class).to receive(:check_existence_for_druid).with(row.first)
      end
      described_class.check_existence_for_druid_list(csv_file_path)
    end
  end

  describe ".seed_catalog_for_dir" do
    it "calls 'find_moab_paths' with appropriate argument" do
      expect(Stanford::MoabStorageDirectory).to receive(:find_moab_paths).with(storage_dir)
      described_class.seed_catalog_for_dir(storage_dir)
    end

    it 'gets moab size and current version from Moab::StorageObject' do
      expect(moab).to receive(:size).at_least(:once)
      expect(moab).to receive(:current_version_id).at_least(:once)
      expect(Moab::StorageServices).not_to receive(:new)
      described_class.seed_catalog_for_dir(storage_dir)
    end

    context "(creates after validation)" do
      let(:expected_argument_list) do
        [
          { druid: 'bj102hs9687', storage_root_current_version: 3 },
          { druid: 'bz514sm9647', storage_root_current_version: 3 },
          { druid: 'jj925bx9565', storage_root_current_version: 2 }
        ]
      end

      before do
        expected_argument_list.each do |arg_hash|
          po_handler = instance_double('PreservedObjectHandler')
          arg_hash[:po_handler] = po_handler
          allow(PreservedObjectHandler).to receive(:new).with(
            arg_hash[:druid],
            arg_hash[:storage_root_current_version],
            instance_of(Integer),
            ms_root
          ).and_return(po_handler)
        end
      end

      it "call #create_after_validation" do
        expected_argument_list.each do |arg_hash|
          expect(arg_hash[:po_handler]).to receive(:create_after_validation)
        end
        described_class.seed_catalog_for_dir(storage_dir)
      end
    end

    it "return correct number of results" do
      expect(described_class.seed_catalog_for_dir(storage_dir).count).to eq 3
    end
  end

  describe ".populate_moab_storage_root" do
    before { described_class.seed_catalog_for_all_storage_roots }

    it "won't change objects in a fully seeded db" do
      expect { described_class.populate_moab_storage_root('fixture_sr1') }.not_to change(CompleteMoab, :count).from(16)
      expect(PreservedObject.count).to eq 16
    end

    it 're-adds objects for a dropped MoabStorageRoot' do
      ZippedMoabVersion.destroy_all
      ms_root.complete_moabs.destroy_all
      PreservedObject.without_complete_moabs.destroy_all
      expect(PreservedObject.count).to eq 13
      expect { described_class.populate_moab_storage_root('fixture_sr1') }.to change(CompleteMoab, :count).from(13).to(16)
      expect(PreservedObject.count).to eq 16
    end
  end
end
