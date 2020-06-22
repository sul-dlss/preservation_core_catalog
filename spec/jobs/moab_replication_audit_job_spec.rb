# frozen_string_literal: true

require 'rails_helper'

describe MoabReplicationAuditJob, type: :job do
  let(:preserved_object) { create(:preserved_object, current_version: 2) }
  let(:job) { described_class.new(preserved_object) }
  let(:logger) { instance_double(Logger) }

  before do
    allow(Audit::CatalogToArchive).to receive(:logger).and_return(logger)
    allow(Settings.replication).to receive(:audit_should_backfill).and_return(true) # enable for tests
    # creation of complete moab triggers archive zip creation, as archive zips are created from moabs
    create(:complete_moab, preserved_object: preserved_object, version: preserved_object.current_version)
  end

  describe '#perform' do
    context 'when there are no zipped moab versions to backfill' do
      it 'does not log a warning' do
        expect(logger).not_to receive(:warn)
        expect { job.perform(preserved_object) }.not_to change(ZippedMoabVersion, :count)
      end
    end

    context 'when there are zipped_moab_versions to backfill' do
      before { preserved_object.zipped_moab_versions.destroy_all } # undo auto-spawned rows from callback

      it 'does nothing when backfilling is disabled' do
        allow(Settings.replication).to receive(:audit_should_backfill).and_return(false)
        expect(preserved_object).not_to receive(:create_zipped_moab_versions!)
        expect { job.perform(preserved_object) }.not_to change(ZippedMoabVersion, :count)
      end

      it 'creates missing ZMVs and logs a warning' do
        expect(preserved_object).to receive(:create_zipped_moab_versions!).and_call_original
        expect(logger).to receive(:warn)
          .with(/backfilled 4 ZippedMoabVersions: 1 to aws_s3_west_2; 1 to ibm_us_south; 2 to aws_s3_west_2; 2 to ibm_us_south/)
        job.perform(preserved_object)
      end
    end

    it 'updates last_archive_audit timestamp' do
      expect { job.perform(preserved_object) }.to change { preserved_object.reload.last_archive_audit }
    end

    it 'calls PartReplicationAuditJob once per related endpoint' do
      new_target_endpoint = create(:zip_endpoint)
      new_nontarget_endpoint = create(:zip_endpoint,
                                      preservation_policies: [create(:preservation_policy, preservation_policy_name: 'giant_datasets_policy')])
      preserved_object.create_zipped_moab_versions! # backfill to the new target endpoint, should omit the other non-default policy endpoint

      expect(preserved_object.zipped_moab_versions.pluck(:zip_endpoint_id).uniq).to include(new_target_endpoint.id)
      PreservationPolicy.default_policy.zip_endpoints.each do |endpoint|
        expect(PartReplicationAuditJob).to receive(:perform_later).with(preserved_object, endpoint)
      end
      expect(PartReplicationAuditJob).not_to receive(:perform_later).with(preserved_object, new_nontarget_endpoint)
      job.perform(preserved_object)
    end
  end
end
