# frozen_string_literal: true

RSpec.shared_examples 's3 audit' do |provider_class, bucket_name, check_name, endpoint_name, region|
  let(:zip_endpoint) do
    ZipEndpoint.find_by(endpoint_name: endpoint_name)
  end
  let(:zmv) do
    create(:zipped_moab_version, zip_endpoint: zip_endpoint)
  end
  let(:bucket) { instance_double(::Aws::S3::Bucket) }
  let(:bucket_name) { bucket_name }
  let(:matching_md5) { attributes_for(:zip_part)[:md5] }
  let(:non_matching_md5) { 'asdfasdfb43t347l;x5px54xx6549;f4' }
  let(:results) { AuditResults.new(zmv.preserved_object.druid, nil, zmv.zip_endpoint, check_name) }
  let(:endpoint_name) { zmv.zip_endpoint.endpoint_name }
  let(:provider) { instance_double(provider_class) }

  before do
    allow(AuditResults).to receive(:new).and_return(results)
    allow(provider_class).to receive(:new).and_return(provider)
    allow(provider).to receive(:bucket).and_return(bucket)
    allow(provider).to receive(:bucket_name).and_return(bucket_name)
  end

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

      # fine to assume existence and matching checksum for all parts for this test case
      allow(bucket).to receive(:object).and_return(
        instance_double(::Aws::S3::Object, exists?: true, metadata: { 'checksum_md5' => args[:md5] })
      )
    end

    it 'only checks existence and checksum on replicated parts' do
      ok_part = zmv.zip_parts.find_by(suffix: '.z01')
      s3_obj = instance_double(::Aws::S3::Object, exists?: true)

      expect(bucket).to receive(:object).with(ok_part.s3_key).and_return(s3_obj)
      expect(s3_obj).to receive(:metadata).and_return('checksum_md5' => ok_part.md5)
      expect { described_class.check_replicated_zipped_moab_version(zmv, results) }
        .to change { ok_part.reload.last_existence_check }.from(nil)
                                                          .and change { ok_part.reload.last_checksum_validation }.from(nil)
    end

    it 'configures S3' do
      described_class.check_replicated_zipped_moab_version(zmv, results)
      # Note that access_key_id and secret_access_key are provided by env variables in CI, via the usual config gem
      # override naming convention, e.g. SETTINGS__zip_endpoints__aws_s3_west_2__access_key_id
      expect(provider_class).to have_received(:new).with(region: region,
                                                         access_key_id: Settings.zip_endpoints[endpoint_name].access_key_id,
                                                         secret_access_key: Settings.zip_endpoints[endpoint_name].secret_access_key)
    end
  end

  context 'all parts listed as ok, but no parts exist on s3' do
    before do
      args = attributes_for(:zip_part)
      zmv.zip_parts.create!(
        [
          args.merge(status: 'ok', parts_count: 3, suffix: '.zip'),
          args.merge(status: 'ok', parts_count: 3, suffix: '.z01'),
          args.merge(status: 'ok', parts_count: 3, suffix: '.z02')
        ]
      )

      # fine to assume non-existence (and thus checksum irrelevance) for all parts for this test case
      allow(bucket).to receive(:object).and_return(
        instance_double(::Aws::S3::Object, exists?: false)
      )
    end

    it 'logs the missing parts and sets status to not_found' do
      described_class.check_replicated_zipped_moab_version(zmv, results)
      zmv.zip_parts.each do |part|
        msg = "replicated part not found on #{endpoint_name}: #{part.s3_key} was not found on #{bucket_name}"
        expect(results.result_array).to include(
          a_hash_including(AuditResults::ZIP_PART_NOT_FOUND => msg)
        )
        expect(part.status).to eq('not_found')
      end
    end
  end

  context 'all parts exist on s3' do
    before do
      args = attributes_for(:zip_part)
      zmv.zip_parts.create!(
        [
          args.merge(status: 'ok', parts_count: 3, suffix: '.zip'),
          args.merge(status: 'ok', parts_count: 3, suffix: '.z01'),
          args.merge(status: 'ok', parts_count: 3, suffix: '.z02')
        ]
      )

      zmv.zip_parts.each_with_index do |part, idx|
        allow(bucket).to receive(:object).with(part.s3_key).and_return(
          instance_double(::Aws::S3::Object, exists?: true, metadata: { 'checksum_md5' => replicated_checksums[idx] })
        )
      end
    end

    context 'all checksums match' do
      let(:replicated_checksums) do
        [matching_md5, matching_md5, matching_md5]
      end

      it "doesn't log checksum mismatches" do
        described_class.check_replicated_zipped_moab_version(zmv, results)
        expect(results.result_array).not_to include(a_hash_including(AuditResults::ZIP_PART_CHECKSUM_MISMATCH))
      end

      it "doesn't log not found errors" do
        described_class.check_replicated_zipped_moab_version(zmv, results)
        expect(results.result_array).not_to include(a_hash_including(AuditResults::ZIP_PART_NOT_FOUND))
      end

      it 'updates existence check timestamps' do
        expect { described_class.check_replicated_zipped_moab_version(zmv, results) }
          .to change { zmv.zip_parts.first.reload.last_existence_check }
          .from(nil)
          .and change { zmv.zip_parts.second.reload.last_existence_check }
          .from(nil)
          .and change { zmv.zip_parts.third.reload.last_existence_check }
          .from(nil)
      end

      it 'updates checksum validation timestamps' do
        expect { described_class.check_replicated_zipped_moab_version(zmv, results) }
          .to change { zmv.zip_parts.first.reload.last_checksum_validation }
          .from(nil)
          .and change { zmv.zip_parts.second.reload.last_checksum_validation }
          .from(nil)
          .and change { zmv.zip_parts.third.reload.last_checksum_validation }
          .from(nil)
      end
    end

    context 'not all checksums match' do
      let(:replicated_checksums) do
        [non_matching_md5, non_matching_md5, matching_md5]
      end

      it 'logs the mismatches' do
        described_class.check_replicated_zipped_moab_version(zmv, results)
        zmv.zip_parts.where(suffix: ['.zip', '.z01']).each do |part|
          msg = "replicated md5 mismatch on #{endpoint_name}: #{part.s3_key} catalog md5 (#{part.md5})"\
            " doesn't match the replicated md5 (#{non_matching_md5}) on #{bucket_name}"
          expect(results.result_array).to include(a_hash_including(AuditResults::ZIP_PART_CHECKSUM_MISMATCH => msg))
        end
      end

      it 'updates existence check timestamps' do
        expect { described_class.check_replicated_zipped_moab_version(zmv, results) }
          .to change { zmv.zip_parts.first.reload.last_existence_check }
          .from(nil)
          .and change { zmv.zip_parts.second.reload.last_existence_check }
          .from(nil)
          .and change { zmv.zip_parts.third.reload.last_existence_check }
          .from(nil)
      end

      it 'updates validation timestamps' do
        expect { described_class.check_replicated_zipped_moab_version(zmv, results) }
          .to change { zmv.zip_parts.first.reload.last_checksum_validation }
          .from(nil)
          .and change { zmv.zip_parts.second.reload.last_checksum_validation }
          .from(nil)
          .and change { zmv.zip_parts.third.reload.last_checksum_validation }
          .from(nil)
      end

      it 'updates status to replicated_checksum_mismatch' do
        expect { described_class.check_replicated_zipped_moab_version(zmv, results) }
          .to change { zmv.zip_parts.first.reload.status }
          .to('replicated_checksum_mismatch')
          .and change { zmv.zip_parts.second.reload.status }
          .to('replicated_checksum_mismatch')
        expect { described_class.check_replicated_zipped_moab_version(zmv, results) }
          .not_to(change { zmv.zip_parts.third.reload.status })
      end
    end
  end

  context 'not all parts exist on s3' do
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

      allow(bucket).to receive(:object).with(zmv.zip_parts.first.s3_key).and_return(
        instance_double(::Aws::S3::Object, exists?: false)
      )
      allow(bucket).to receive(:object).with(zmv.zip_parts.second.s3_key).and_return(
        instance_double(::Aws::S3::Object, exists?: true, metadata: { 'checksum_md5' => replicated_checksums.second })
      )
      allow(bucket).to receive(:object).with(zmv.zip_parts.third.s3_key).and_return(
        instance_double(::Aws::S3::Object, exists?: true, metadata: { 'checksum_md5' => replicated_checksums.third })
      )
      allow(bucket).to receive(:object).with(zmv.zip_parts.fourth.s3_key).and_return(
        instance_double(::Aws::S3::Object, exists?: false)
      )
    end

    context 'all parts that do exist have matching checksums' do
      let(:replicated_checksums) do
        [matching_md5, matching_md5, matching_md5, matching_md5]
      end

      it 'logs the missing parts' do
        described_class.check_replicated_zipped_moab_version(zmv, results)

        [zmv.zip_parts.first, zmv.zip_parts.fourth].each do |part|
          msg = "replicated part not found on #{endpoint_name}: #{part.s3_key} was not found on #{bucket_name}"
          expect(results.result_array).to include(a_hash_including(AuditResults::ZIP_PART_NOT_FOUND => msg))
        end
      end

      it "doesn't log checksum mismatches" do
        described_class.check_replicated_zipped_moab_version(zmv, results)
        expect(results.result_array).not_to include(a_hash_including(AuditResults::ZIP_PART_CHECKSUM_MISMATCH))
      end
    end

    context 'some parts that do exist have checksums that do not match' do
      let(:replicated_checksums) do
        [non_matching_md5, non_matching_md5, matching_md5, matching_md5]
      end

      it 'logs the missing parts' do
        described_class.check_replicated_zipped_moab_version(zmv, results)
        [zmv.zip_parts.first, zmv.zip_parts.fourth].each do |part|
          msg = "replicated part not found on #{endpoint_name}: #{part.s3_key} was not found on #{bucket_name}"
          expect(results.result_array).to include(a_hash_including(AuditResults::ZIP_PART_NOT_FOUND => msg))
        end
      end

      it 'logs the checksum mismatches' do
        part = zmv.zip_parts.second
        msg = "replicated md5 mismatch on #{endpoint_name}: #{part.s3_key} catalog md5 (#{part.md5}) "\
          "doesn't match the replicated md5 (#{non_matching_md5}) on #{bucket_name}"
        described_class.check_replicated_zipped_moab_version(zmv, results)
        expect(results.result_array).to include(a_hash_including(AuditResults::ZIP_PART_CHECKSUM_MISMATCH => msg))
      end
    end
  end
end
