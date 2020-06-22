# frozen_string_literal: true

require 'rails_helper'

describe ZipmakerJob, type: :job do
  let(:druid) { 'bj102hs9687' }
  let(:dvz_part) { instance_double(DruidVersionZipPart, metadata: { fake: 1 }) }
  let(:version) { 1 }
  let(:zip_path) { "spec/fixtures/zip_storage/bj/102/hs/9687/#{druid}#{format('.v%04d.zip', version)}" }
  let(:druid_version_zip) { DruidVersionZip.new(druid, version, moab_replication_storage_location) }
  let(:moab_replication_storage_location) { '/path/to/moab' }

  before do
    allow(PlexerJob).to receive(:perform_later).with(any_args)
    allow(Settings).to receive(:zip_storage).and_return('spec/fixtures/zip_storage')
    allow(DruidVersionZip).to receive(:new).with(druid, version, moab_replication_storage_location).and_return(druid_version_zip)
  end

  it 'invokes PlexerJob (single part zip)' do
    expect(PlexerJob).to receive(:perform_later).with(druid, version, 'bj/102/hs/9687/bj102hs9687.v0001.zip', Hash)
    described_class.perform_now(druid, version, moab_replication_storage_location)
  end

  it 'handles segmented zips, invokes PlexerJob per part' do
    allow(DruidVersionZipPart).to receive(:new).and_return(dvz_part)
    allow(druid_version_zip).to receive(:part_keys).and_return(
      [
        'bj/102/hs/9687/bj102hs9687.v0001.zip',
        'bj/102/hs/9687/bj102hs9687.v0001.z01',
        'bj/102/hs/9687/bj102hs9687.v0001.z02'
      ]
    )
    expect(PlexerJob).to receive(:perform_later).with(druid, version, 'bj/102/hs/9687/bj102hs9687.v0001.zip', Hash)
    expect(PlexerJob).to receive(:perform_later).with(druid, version, 'bj/102/hs/9687/bj102hs9687.v0001.z01', Hash)
    expect(PlexerJob).to receive(:perform_later).with(druid, version, 'bj/102/hs/9687/bj102hs9687.v0001.z02', Hash)
    described_class.perform_now(druid, version, moab_replication_storage_location)
  end

  context 'zip already exists in zip storage' do
    it 'does not create a zip, but touches the existing one' do
      expect(File).to exist(zip_path)
      expect(FileUtils).to receive(:touch).with(druid_version_zip.file_path)
      expect(druid_version_zip).not_to receive(:create_zip!)
      described_class.perform_now(druid, version, moab_replication_storage_location)
    end
  end

  context 'zip is not yet in zip storage' do
    let(:version) { 3 }

    before { allow(DruidVersionZipPart).to receive(:new).and_return(dvz_part) }

    it 'creates the zip' do
      expect(File).not_to exist(zip_path)
      expect(druid_version_zip).to receive(:create_zip!)
      described_class.perform_now(druid, version, moab_replication_storage_location)
    end
  end
end
