require 'rails_helper'

describe PreservationCatalog::S3 do
  describe '.bucket_name' do
    context 'without ENV variable' do
      it 'returns value from Settings' do
        expect(described_class.bucket_name).to eq 'sul-sdr-aws-us-west-2-test'
      end
    end
    context 'with ENV variable AWS_BUCKET_NAME' do
      around do |example|
        old_val = ENV['AWS_BUCKET_NAME']
        ENV['AWS_BUCKET_NAME'] = 'bucket_44'
        example.run
        ENV['AWS_BUCKET_NAME'] = old_val
      end
      it 'returns the ENV value' do
        expect(described_class.bucket_name).to eq 'bucket_44'
      end
    end
  end

  describe 'config' do
    context 'with access key and region env vars' do
      let(:config) { described_class.client.config }
      let(:envs) do
        {
          'AWS_SECRET_ACCESS_KEY' => 'secret',
          'AWS_ACCESS_KEY_ID' => 'some_key',
          'AWS_REGION' => 'us-east-1'
        }
      end

      around do |example|
        old_vals = envs.keys.zip(ENV.values_at(*envs.keys)).to_h
        envs.each { |k, v| ENV[k] = v }
        example.run
        old_vals.each { |k, v| ENV[k] = v }
      end
      it 'pulls from ENV vars' do
        expect(config.region).to eq 'us-east-1'
        expect(config.credentials).to be_an(Aws::Credentials)
        expect(config.credentials).to be_set
        expect(config.credentials.access_key_id).to eq 'some_key'
      end
    end

    context 'pointing the client to shared credentials' do
      let(:config) { described_class.client.config }
      let(:shared_credentials) do
        Aws::SharedCredentials.new(path: Rails.root.join('spec', 'fixtures', 'aws_credentials'))
      end

      after do
        Aws.config = {}
      end

      context 'profile us_west_2' do
        let(:envs) { Hash['AWS_PROFILE' => 'us_west_2'] }

        around do |example|
          old_vals = envs.keys.zip(ENV.values_at(*envs.keys)).to_h
          envs.each { |k, v| ENV[k] = v }
          example.run
          old_vals.each { |k, v| ENV[k] = v }
        end

        it 'pulls the one profile from a config file' do
          Aws.config.update(region: 'us-west-2', credentials: shared_credentials)
          expect(config.region).to eq 'us-west-2'
          expect(config.credentials.credentials.access_key_id).to eq 'foo'
          expect(config.credentials.credentials.secret_access_key).to eq 'bar'
        end
      end
      context 'profile us_east_1' do
        let(:envs) { Hash['AWS_PROFILE' => 'us_east_1'] }

        around do |example|
          old_vals = envs.keys.zip(ENV.values_at(*envs.keys)).to_h
          envs.each { |k, v| ENV[k] = v }
          example.run
          old_vals.each { |k, v| ENV[k] = v }
        end
        it 'pulls the other profile from a config file' do
          Aws.config.update(region: 'us-east-1', credentials: shared_credentials)
          expect(config.region).to eq 'us-east-1'
          expect(config.credentials.credentials.access_key_id).to eq 'baz'
          expect(config.credentials.credentials.secret_access_key).to eq 'quux'
        end
      end
    end
  end

  context 'Live S3 bucket', live_s3: true do
    subject(:bucket) { described_class.bucket }

    it { is_expected.to exist }

    describe 'Aws::S3::Object#upload_file' do
      subject(:s3_object) { bucket.object("test_key_#{test_key_id}") }

      let(:test_key_id) { ENV.fetch('TRAVIS_JOB_ID', '000') }
      let(:dvz) { DruidVersionZip.new('bj102hs9687', 2) }
      let(:dvz_part) { DruidVersionZipPart.new(dvz, dvz.s3_key('.zip')) }
      let(:digest) { dvz_part.base64digest }
      let(:now) { Time.zone.now.iso8601 }
      let(:get_response) { s3_object.get }

      before do
        allow(Settings).to receive(:zip_storage).and_return(Rails.root.join('spec', 'fixtures', 'zip_storage'))
      end

      it 'accepts/returns File body and arbitrary metadata' do
        resp = nil
        expect { s3_object.upload_file(dvz_part.file_path, metadata: { our_time: now }) }.not_to raise_error
        expect { resp = s3_object.get }.not_to raise_error
        expect(resp).to be_a(Aws::S3::Types::GetObjectOutput)
        expect(resp.metadata.symbolize_keys).to eq(our_time: now)
        expect(resp.body.read).to eq("FOOOOBAR\n")
      end
    end
  end
end
