# frozen_string_literal: true

require 'rails_helper'

describe PartReplicationAuditJob, type: :job do
  let(:preserved_object) { create(:preserved_object, current_version: 2) }
  let(:job) { described_class.new(preserved_object, endpoint) }
  let(:endpoints) { preserved_object.zipped_moab_versions.map(&:zip_endpoint).uniq }
  let(:endpoint) { endpoints.first }
  let(:endpoint2) { endpoints.second }
  let(:logger) { instance_double(Logger) }

  before do
    allow(Audit::CatalogToArchive).to receive(:logger).and_return(logger)
    # creation of complete moab triggers archive zip creation, as archive zips are created from moabs
    create(:complete_moab, preserved_object: preserved_object, version: preserved_object.current_version)
  end

  describe '#queue_as' do
    it 'builds the queue name' do
      expect(job.queue_name).to eq("part_audit_#{endpoint.endpoint_name}")
    end

    context 'with a different endpoint' do
      let(:endpoint) { create(:zip_endpoint, endpoint_name: 'north_foobar') }

      it 'adapts the queue name' do
        expect(job.queue_name).to eq('part_audit_north_foobar')
      end
    end
  end

  describe '#perform' do
    let(:zmv1) { preserved_object.zipped_moab_versions.where(zip_endpoint: endpoint).first }
    let(:zmv2) { preserved_object.zipped_moab_versions.where(zip_endpoint: endpoint).second }
    let(:zmv3) { preserved_object.zipped_moab_versions.where(zip_endpoint: endpoint2).first }
    let(:zmv4) { preserved_object.zipped_moab_versions.where(zip_endpoint: endpoint2).second }
    let(:results) { job.send(:new_results) }
    let(:audit_class) { endpoint.audit_class }
    let(:audit_class2) { endpoint2.audit_class }

    it 'includes the name of the endpoint in the reported results' do
      allow(job).to receive(:new_results).and_return(results)
      allow(job).to receive(:check_child_zip_part_attributes).with(zmv1, AuditResults).and_return(false)
      allow(job).to receive(:check_child_zip_part_attributes).with(zmv2, AuditResults).and_return(false)
      job.perform(preserved_object, endpoint)
      expect(results.results_as_string).to match(/actual location: #{endpoint.endpoint_name}/)
    end

    it 'only checks parts for one endpoint' do
      other_ep = create(:zip_endpoint)
      preserved_object.create_zipped_moab_versions! # backfill endpoint added since CompleteMoab was created (triggering replication) in before block
      other_zmv = preserved_object.zipped_moab_versions.find_by!(zip_endpoint: other_ep)
      count = preserved_object.zipped_moab_versions.where(zip_endpoint: endpoint).count
      expect(job).to receive(:check_child_zip_part_attributes).with(ZippedMoabVersion, AuditResults).exactly(count).times
      expect(job).not_to receive(:check_child_zip_part_attributes).with(other_zmv, AuditResults)
      job.perform(preserved_object, endpoint)
    end

    it 'builds results from sub-checks, only for the given endpoint' do
      allow(job).to receive(:new_results).and_return(results)
      allow(job).to receive(:check_child_zip_part_attributes).with(zmv2, AuditResults)
      expect(job).to receive(:check_child_zip_part_attributes).with(zmv1, AuditResults).and_return(true)
      expect(audit_class).to receive(:check_replicated_zipped_moab_version).with(zmv1, AuditResults)
      expect(audit_class).not_to receive(:check_replicated_zipped_moab_version).with(zmv2, AuditResults)
      expect(audit_class2).not_to receive(:check_replicated_zipped_moab_version)
      expect(results).to receive(:report_results)
      job.perform(preserved_object, endpoint)
    end

    it 'checks the other endpoint when requested' do
      allow(job).to receive(:new_results).and_return(results)
      allow(job).to receive(:check_child_zip_part_attributes).with(zmv3, results).and_return(true)
      allow(job).to receive(:check_child_zip_part_attributes).with(zmv4, results).and_return(true)
      expect(audit_class).not_to receive(:check_replicated_zipped_moab_version)
      expect(audit_class2).not_to receive(:check_replicated_zipped_moab_version).with(zmv1, AuditResults)
      expect(audit_class2).not_to receive(:check_replicated_zipped_moab_version).with(zmv2, AuditResults)
      expect(audit_class2).to receive(:check_replicated_zipped_moab_version).with(zmv3, results)
      expect(audit_class2).to receive(:check_replicated_zipped_moab_version).with(zmv4, results)
      job.perform(preserved_object, endpoint2)
    end
  end
end
