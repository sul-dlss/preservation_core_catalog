require 'rails_helper'

describe S3WestDeliveryJob, type: :job do
  let(:druid) { 'bj102hs9687' }
  let(:version) { 1 }
  let(:dvz) { DruidVersionZip.new(druid, version) }
  let(:dvz_part) { DruidVersionZipPart.new(dvz, part_s3_key) }
  let(:object) { instance_double(Aws::S3::Object, exists?: false, upload_file: true) }
  let(:bucket) { instance_double(Aws::S3::Bucket, object: object) }
  let(:md5) { '4f98f59e877ecb84ff75ef0fab45bac5' }
  let(:base64) { dvz.hex_to_base64(md5) }
  let(:metadata) { dvz_part.metadata.merge(zip_version: 'Zip 3.0 (July 5th 2008)') }
  let(:part_s3_key) { dvz.s3_key('.zip') }

  before do
    allow(Settings).to receive(:zip_storage).and_return(Rails.root.join('spec', 'fixtures', 'zip_storage'))
    allow(PreservationCatalog::S3).to receive(:bucket).and_return(bucket)
    allow(ResultsRecorderJob).to receive(:perform_later).with(any_args)
  end

  it 'descends from ZipPartJobBase' do
    expect(described_class.new).to be_an(ZipPartJobBase)
  end

  context 'zip part already exists on s3' do
    before { allow(object).to receive(:exists?).and_return(true) }

    it 'does nothing' do
      expect(object).not_to receive(:upload_file)
      expect(ResultsRecorderJob).not_to receive(:perform_later)
      described_class.perform_now(druid, version, part_s3_key, metadata)
    end
  end

  context 'zip part is new to S3' do
    it 'uploads_file to S3' do
      expect(object).to receive(:upload_file).with(
        dvz_part.file_path, metadata: a_hash_including(checksum_md5: md5)
      )
      described_class.perform_now(druid, version, part_s3_key, metadata)
    end
    it 'invokes ResultsRecorderJob' do
      expect(ResultsRecorderJob).to receive(:perform_later).with(druid, version, part_s3_key, described_class.to_s)
      described_class.perform_now(druid, version, part_s3_key, metadata)
    end
  end
end
