# frozen_string_literal: true

require 'rails_helper'

describe 'the whole replication pipeline', type: :job do # rubocop:disable RSpec/DescribeClass
  let(:aws_s3_object) { instance_double(::Aws::S3::Object, exists?: false, upload_file: true) }
  let(:ibm_s3_object) { instance_double(::Aws::S3::Object, exists?: false, upload_file: true) }
  let(:aws_bucket) { instance_double(::Aws::S3::Bucket, object: aws_s3_object) }
  let(:ibm_bucket) { instance_double(::Aws::S3::Bucket, object: ibm_s3_object) }
  let(:preserved_object) { create(:preserved_object) }
  let(:druid) { preserved_object.druid }
  let(:version) { preserved_object.current_version }
  let(:zip_endpoints) { preserved_object.preservation_policy.zip_endpoints }
  let(:hash) do
    {
      druid: druid,
      version: version,
      zip_endpoints: zip_endpoints.map(&:endpoint_name).sort
    }
  end
  let(:s3_key) { 'bj/102/hs/9687/bj102hs9687.v0001.zip' }
  let(:aws_provider) { instance_double(PreservationCatalog::AwsProvider, bucket: aws_bucket) }
  let(:ibm_provider) { instance_double(PreservationCatalog::IbmProvider, bucket: ibm_bucket) }
  let(:moab_storage_root) { create(:moab_storage_root) }

  around do |example|
    old_adapter = ApplicationJob.queue_adapter
    ApplicationJob.queue_adapter = :inline
    example.run
    ApplicationJob.queue_adapter = old_adapter
  end

  before do
    FactoryBot.reload # we need the "first" PO, bj102hs9687, for PC to line up w/ fixture
    allow(Settings).to receive(:zip_storage).and_return(Rails.root.join('spec', 'fixtures', 'zip_storage'))
    allow(PreservationCatalog::AwsProvider).to receive(:new).and_return(aws_provider)
    allow(PreservationCatalog::IbmProvider).to receive(:new).and_return(ibm_provider)
  end

  it 'gets from zipmaker queue to replication result message' do
    expect(ZipmakerJob).to receive(:perform_later).with(druid, version, moab_storage_root.storage_location).and_call_original
    expect(PlexerJob).to receive(:perform_later).with(druid, version, s3_key, Hash).and_call_original
    expect(S3WestDeliveryJob).to receive(:perform_later).with(druid, version, s3_key, Hash).and_call_original
    expect(IbmSouthDeliveryJob).to receive(:perform_later).with(druid, version, s3_key, Hash).and_call_original
    # other endpoints as added...
    expect(ResultsRecorderJob).to receive(:perform_later).with(druid, version, s3_key, 'S3WestDeliveryJob').and_call_original
    expect(ResultsRecorderJob).to receive(:perform_later).with(druid, version, s3_key, 'IbmSouthDeliveryJob').and_call_original
    expect(Resque.redis.redis).to receive(:lpush).with('replication.results', hash.to_json)

    # creating or updating a CompleteMoab should trigger its parent PreservedObject to replicate any missing versions to any target endpoints
    create(:complete_moab, preserved_object: preserved_object, version: preserved_object.current_version, moab_storage_root: moab_storage_root)
  end
end
