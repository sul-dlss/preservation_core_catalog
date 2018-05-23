require 'rails_helper'

describe 'the whole replication pipeline', type: :job do # rubocop:disable RSpec/DescribeClass
  let(:s3_object) { instance_double(Aws::S3::Object, exists?: false, put: true) }
  let(:bucket) { instance_double(Aws::S3::Bucket, object: s3_object) }
  let(:druid) { pc.preserved_object.druid }
  let(:version) { pc.version }
  let(:deliverer) { S3EndpointDeliveryJob.to_s }
  let(:hash) do
    { druid: druid, version: version, endpoints: [pc.endpoint.endpoint_name] }
  end
  let(:pc) { create(:unreplicated_copy) }

  around do |example|
    old_adapter = ApplicationJob.queue_adapter
    ApplicationJob.queue_adapter = :inline
    example.run
    ApplicationJob.queue_adapter = old_adapter
  end

  before do
    allow(Settings).to receive(:zip_storage).and_return(Rails.root.join('spec', 'fixtures', 'zip_storage'))
    allow(PreservationCatalog::S3).to receive(:bucket).and_return(bucket)
  end

  it 'gets from zipmaker queue to replication result message' do
    expect(PlexerJob).to receive(:perform_later).with(druid, version).and_call_original
    expect(S3EndpointDeliveryJob).to receive(:perform_later).with(druid, version).and_call_original
    # other endpoints as added...
    expect(ResultsRecorderJob).to receive(:perform_later).with(druid, version, deliverer, '12345ABC').and_call_original
    expect(Resque.redis.redis).to receive(:lpush).with('replication.results', hash.to_json)
    ZipmakerJob.perform_now(druid, version)
  end
end
