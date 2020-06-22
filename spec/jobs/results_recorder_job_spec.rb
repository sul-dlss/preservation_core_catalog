# frozen_string_literal: true

require 'rails_helper'

describe ResultsRecorderJob, type: :job do
  let(:preserved_object) { create(:preserved_object) }
  let(:zmv) { preserved_object.zipped_moab_versions.first }
  let(:zmv2) { preserved_object.zipped_moab_versions.second }
  let(:druid) { preserved_object.druid }
  let(:zip_endpoint) { zmv.zip_endpoint }
  let(:zip_endpoint2) { zmv2.zip_endpoint }

  before do
    # creating the CompleteMoab triggers associated ZippedMoabVersion creation via AR hooks
    create(:complete_moab, preserved_object: preserved_object, version: preserved_object.current_version)
    zmv.zip_parts.create(attributes_for(:zip_part))
    zmv2.zip_parts.create(attributes_for(:zip_part))
  end

  it 'descends from ApplicationJob' do
    expect(described_class.new).to be_an(ApplicationJob)
  end

  context 'when all parts for zip_endpoint are replicated' do
    it 'sets part status to ok' do
      expect {
        described_class.perform_now(druid, zmv.version, 'fake.zip', zip_endpoint.delivery_class.to_s)
      }.to change {
        zmv.zip_parts.first.status
      }.from('unreplicated').to('ok')
    end
  end

  context 'when all zip_endpoints are fulfilled' do
    it 'posts a message to replication.results queue' do
      hash = { druid: druid, version: zmv.version, zip_endpoints: [zip_endpoint.endpoint_name, zip_endpoint2.endpoint_name].sort }
      expect(Resque.redis.redis).to receive(:lpush).with('replication.results', hash.to_json)
      described_class.perform_now(druid, zmv.version, 'fake.zip', zip_endpoint.delivery_class.to_s)
      described_class.perform_now(druid, zmv2.version, 'fake.zip', zip_endpoint2.delivery_class.to_s)
    end
  end

  context 'when other endpoints remain unreplicated' do
    let(:other_ep) { create(:zip_endpoint, delivery_class: 2) }

    before do
      preserved_object.zipped_moab_versions.create!(version: zmv.version, zip_endpoint: other_ep)
    end

    it 'does not send to replication.results queue' do
      expect(Resque.redis.redis).not_to receive(:lpush)
      described_class.perform_now(druid, zmv.version, 'fake.zip', zip_endpoint.delivery_class.to_s)
    end
  end
end
