# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChecksumValidator do
  let(:druid) { 'zz102hs9687' }
  let(:root_name) { 'fixture_sr3' }
  let(:ms_root) { MoabStorageRoot.find_by!(name: root_name) }
  let(:object_dir) { "#{ms_root.storage_location}/#{DruidTools::Druid.new(druid).tree.join('/')}" }
  let(:comp_moab) do
    create(:preserved_object_fixture, druid: druid).complete_moabs.find_by!(moab_storage_root: ms_root)
  end
  let(:cv) { described_class.new(comp_moab) }
  let(:moab_validator) { cv.send(:moab_validator) }
  let(:results) { instance_double(AuditResults, report_results: nil, check_name: nil, :actual_version= => nil) }
  let(:logger_double) { instance_double(ActiveSupport::Logger, info: nil, error: nil, add: nil) }
  let(:workflow_reporter) { instance_double(Reporters::WorkflowReporter, report_errors: nil, report_completed: nil) }
  let(:honeybadger_reporter) { instance_double(Reporters::HoneybadgerReporter, report_errors: nil, report_completed: nil) }
  let(:event_service_reporter) { instance_double(Reporters::EventServiceReporter, report_errors: nil, report_completed: nil) }
  let(:logger_reporter) { instance_double(Reporters::LoggerReporter, report_errors: nil, report_completed: nil) }

  before do
    allow(Audit::Checksum).to receive(:logger).and_return(logger_double) # silence log output
    allow(Reporters::LoggerReporter).to receive(:new).and_return(logger_reporter)
    allow(Reporters::WorkflowReporter).to receive(:new).and_return(workflow_reporter)
    allow(Reporters::HoneybadgerReporter).to receive(:new).and_return(honeybadger_reporter)
    allow(Reporters::EventServiceReporter).to receive(:new).and_return(event_service_reporter)
  end

  describe '#initialize' do
    it 'sets attributes' do
      expect(cv.complete_moab).to eq comp_moab
      expect(cv.bare_druid).to eq druid
      expect(cv.moab_storage_root).to eq ms_root
      expect(cv.results).to be_an_instance_of AuditResults
      expect(cv.results.actual_version).to eq 3
    end

    it 'instantiates a Moab::StorageObject from druid and druid_path' do
      expect(cv.moab).to be_an_instance_of Moab::StorageObject
      expect(cv.moab.digital_object_id).to eq druid
      expect(cv.moab.object_pathname.to_s).to eq object_dir
    end
  end

  describe '#validate_manifest_inventories' do
    it 'calls validate_manifest_inventory for each moab_version' do
      sov1 = instance_double(Moab::StorageObjectVersion)
      sov2 = instance_double(Moab::StorageObjectVersion)
      sov3 = instance_double(Moab::StorageObjectVersion)
      version_list = [sov1, sov2, sov3]
      moab = instance_double(Moab::StorageObject, version_list: [sov1, sov2, sov3])
      allow(cv).to receive(:moab).and_return(moab)
      version_list.each do |moab_version|
        expect(cv).to receive(:validate_manifest_inventory).with(moab_version)
      end
      cv.validate_manifest_inventories
    end

    context 'file checksums in manifestInventory.xml do not match' do
      let(:druid) { 'zz925bx9565' }
      let(:results) { instance_double(AuditResults, report_results: nil, :actual_version= => nil) }

      before { allow(AuditResults).to receive(:new).and_return(results) }

      it 'adds a MOAB_FILE_CHECKSUM_MISMATCH result' do
        file_path1 = "#{object_dir}/v0001/manifests/versionAdditions.xml"
        file_path2 = "#{object_dir}/v0002/manifests/versionInventory.xml"
        expect(results).to receive(:add_result).with(
          AuditResults::MOAB_FILE_CHECKSUM_MISMATCH, file_path: a_string_matching(file_path1), version: 'v1'
        )
        expect(results).to receive(:add_result).with(
          AuditResults::MOAB_FILE_CHECKSUM_MISMATCH, file_path: a_string_matching(file_path2), version: 'v2'
        )
        cv.validate_manifest_inventories
      end
    end

    context 'file missing from manifestInventory.xml' do
      before { allow(AuditResults).to receive(:new).and_return(results) }

      it 'adds a FILE_NOT_IN_MANIFEST result' do
        manifest_file_path = "#{object_dir}/v0003/manifests/manifestInventory.xml"
        file_path = "#{object_dir}/v0003/manifests/versionInventory.xml"
        expect(results).to receive(:add_result).with(
          AuditResults::FILE_NOT_IN_MANIFEST, file_path: a_string_matching(file_path), manifest_file_path: a_string_matching(manifest_file_path)
        )
        cv.validate_manifest_inventories
      end
    end

    context 'file not on disk, but is described in manifestInventory.xml' do
      let(:druid) { 'zz514sm9647' }

      before { allow(AuditResults).to receive(:new).and_return(results) }

      it 'adds a FILE_NOT_IN_MOAB result' do
        manifest_file_path = "#{object_dir}/v0003/manifests/manifestInventory.xml"
        file_path = "#{object_dir}/v0003/manifests/versionInventory.xml"
        expect(results).to receive(:add_result).with(
          AuditResults::FILE_NOT_IN_MOAB, manifest_file_path: a_string_matching(manifest_file_path), file_path: a_string_matching(file_path)
        )
        cv.validate_manifest_inventories
      end
    end

    context 'manifestInventory.xml not found in Moab' do
      let(:druid) { 'zz628nk4868' }

      before { allow(AuditResults).to receive(:new).and_return(results) }

      it 'adds a MANIFEST_NOT_IN_MOAB' do
        manifest_file_path = 'spec/fixtures/checksum_root01/sdr2objects/zz/628/nk/4868/zz628nk4868/v0001/manifests/manifestInventory.xml'
        expect(results).to receive(:add_result).with(
          AuditResults::MANIFEST_NOT_IN_MOAB, manifest_file_path: manifest_file_path
        )
        cv.validate_manifest_inventories
      end
    end

    context 'cannot parse xml file' do
      let(:druid) { 'zz048cw1328' }

      before { allow(AuditResults).to receive(:new).and_return(results) }

      it 'adds an INVALID_MANIFEST' do
        manifest_file_path = 'spec/fixtures/checksum_root01/sdr2objects/zz/048/cw/1328/zz048cw1328/v0002/manifests/manifestInventory.xml'
        expect(results).to receive(:add_result).with(
          AuditResults::INVALID_MANIFEST, manifest_file_path: manifest_file_path
        )
        cv.validate_manifest_inventories
      end
    end
  end

  describe '#validate_signature_catalog_listing' do
    let(:druid) { 'bj102hs9687' }
    let(:root_name) { 'fixture_sr1' }
    let(:results) { instance_double(AuditResults, report_results: nil, :actual_version= => nil) }

    it 'calls validate_signature_catalog_entry for each signatureCatalog entry' do
      sce01 = instance_double(Moab::SignatureCatalogEntry)
      entry_list = [sce01] + Array.new(10, sce01.dup)
      moab = instance_double(Moab::StorageObject)
      allow(cv).to receive(:moab).and_return(moab)
      allow(cv).to receive(:latest_signature_catalog_entries).and_return(entry_list)
      entry_list.each do |entry|
        expect(cv).to receive(:validate_signature_catalog_entry).with(entry)
      end
      cv.send(:validate_signature_catalog_listing)
    end

    context 'file checksums in singatureCatalog.xml do not match' do
      let(:druid) { 'zz111rr1111' }
      let(:root_name) { 'fixture_sr3' }

      before { allow(AuditResults).to receive(:new).and_return(results) }

      it 'adds a MOAB_FILE_CHECKSUM_MISMATCH result' do
        file_path = "#{object_dir}/v0001/data/content/eric-smith-dissertation-augmented.pdf"
        expect(results).to receive(:add_result).with(
          AuditResults::MOAB_FILE_CHECKSUM_MISMATCH, file_path: file_path, version: 1
        )
        cv.send(:validate_signature_catalog_listing)
      end
    end

    context "SC1258_FUR_032a.jpg not on disk, but it's entry element exists in signatureCatalog.xml" do
      let(:druid) { 'tt222tt2222' }
      let(:root_name) { 'fixture_sr3' }

      before { allow(AuditResults).to receive(:new).and_return(results) }

      it 'adds a FILE_NOT_IN_MOAB error' do
        manifest_file_path = "#{object_dir}/v0003/manifests/signatureCatalog.xml"
        file_path = "#{object_dir}/v0001/data/content/SC1258_FUR_032a.jpg"
        expect(results).to receive(:add_result).with(
          AuditResults::FILE_NOT_IN_MOAB, manifest_file_path: manifest_file_path, file_path: file_path
        )
        cv.send(:validate_signature_catalog_listing)
      end
    end

    context 'signatureCatalog.xml not found in moab' do
      let(:druid) { 'zz333vv3333' }
      let(:root_name) { 'fixture_sr3' }

      before { allow(AuditResults).to receive(:new).and_return(results) }

      it 'adds a MANIFEST_NOT_IN_MOAB error' do
        expect(results).to receive(:add_result).with(
          AuditResults::SIGNATURE_CATALOG_NOT_IN_MOAB, signature_catalog_path: "#{object_dir}/v0002/manifests/signatureCatalog.xml"
        )
        cv.send(:validate_signature_catalog_listing)
      end
    end

    context 'cannot parse signatureCatalog.xml' do
      let(:druid) { 'xx444xx4444' }
      let(:root_name) { 'fixture_sr3' }

      before { allow(AuditResults).to receive(:new).and_return(results) }

      it 'adds an INVALID_MANIFEST error' do
        expect(results).to receive(:add_result).with(
          AuditResults::INVALID_MANIFEST, manifest_file_path: "#{object_dir}/v0001/manifests/signatureCatalog.xml"
        )
        cv.send(:validate_signature_catalog_listing)
      end
    end
  end

  describe '#validate_checksums' do
    context 'moab is missing from storage' do
      let(:events_client) { instance_double(Dor::Services::Client::Events) }

      before do
        # fake a moab gone missing by updating the preserved object to use a non-existent druid
        comp_moab.preserved_object.update(druid: 'tr808sp1200')
        allow(Dor::Services::Client).to receive(:object).with('druid:tr808sp1200').and_return(
          instance_double(Dor::Services::Client::Object, events: events_client)
        )
        allow(events_client).to receive(:create).with(type: 'preservation_audit_failure', data: instance_of(Hash))
      end

      it 'sets status to online_moab_not_found and adds corresponding audit result' do
        expect { cv.validate_checksums }.to change(comp_moab, :status).to 'online_moab_not_found'
        expect(comp_moab.reload.status).to eq 'online_moab_not_found'
        expect(cv.results.result_array.first).to have_key(:moab_not_found)
      end

      it 'sends results in HONEYBADGER_REPORT_CODES errors' do
        reason = 'db CompleteMoab \\(created .*Z; last updated .*Z\\) exists but Moab not found'
        cv.validate_checksums

        expect(honeybadger_reporter).to have_received(:report_errors)
          .with(druid: 'tr808sp1200',
                version: 0,
                storage_area: ms_root,
                check_name: 'validate_checksums',
                results: [{ moab_not_found: match(reason) },
                          { cm_status_changed: 'CompleteMoab status changed from validity_unknown to online_moab_not_found' }])
        expect(event_service_reporter).to have_received(:report_errors)
          .with(druid: 'tr808sp1200',
                version: 0,
                storage_area: ms_root,
                check_name: 'validate_checksums',
                results: [{ moab_not_found: match(reason) },
                          { cm_status_changed: 'CompleteMoab status changed from validity_unknown to online_moab_not_found' }])
      end

      it 'calls AuditResults.report_results' do
        expect(cv.results).to receive(:report_results)
        cv.validate_checksums
      end
    end

    context 'passes checksum validation' do
      let(:druid) { 'bz514sm9647' }
      let(:root_name) { 'fixture_sr1' }

      it 'returns a positive result for a comp_moab' do
        cv.validate_checksums
        expect(cv.results.result_array.first).to have_key(:moab_checksum_valid)
      end

      [
        'online_moab_not_found',
        'invalid_moab',
        'unexpected_version_on_storage',
        'invalid_checksum',
        'validity_unknown'
      ].each do |initial_status|
        it "sets status to OK_STATUS if it was previously #{initial_status}" do
          comp_moab.status = initial_status
          comp_moab.save!
          expect { cv.validate_checksums }.to change(comp_moab, :status).to 'ok'
          expect(comp_moab.reload.status).to eq 'ok'
        end
      end

      it 'leaves status of OK_STATUS as-is' do
        comp_moab.ok!
        expect { cv.validate_checksums }.not_to(change(comp_moab, :status))
        expect(comp_moab.reload.status).to eq 'ok'
      end

      it 'updates audit timestamps' do
        expect(comp_moab.last_moab_validation).to be nil
        expect(comp_moab.last_version_audit).to be nil
        approximate_validation_time = Time.current
        cv.validate_checksums
        expect(comp_moab.last_moab_validation).to be > approximate_validation_time
        expect(comp_moab.last_version_audit).to be > approximate_validation_time
      end

      context 'fails other moab validation' do
        context 'version on disk does not match expected version from catalog' do
          before do
            comp_moab.version = 4 # this is one greater than the version on disk for bz514sm9647
            comp_moab.save!
          end

          [
            'ok',
            'online_moab_not_found',
            'invalid_moab',
            'invalid_checksum',
            'validity_unknown'
          ].each do |initial_status|
            it "sets status to UNEXPECTED_VERSION_ON_STORAGE_STATUS if it was previously #{initial_status}" do
              comp_moab.status = initial_status
              comp_moab.save!
              expect { cv.validate_checksums }.to change(comp_moab, :status).to 'unexpected_version_on_storage'
              expect(cv.results.contains_result_code?(AuditResults::UNEXPECTED_VERSION)).to be true
              expect(comp_moab.reload.status).to eq 'unexpected_version_on_storage'
            end
          end

          it 'leaves status as UNEXPECTED_VERSION_ON_STORAGE_STATUS if complete moab started in that state' do
            comp_moab.unexpected_version_on_storage!
            expect { cv.validate_checksums }.not_to(change(comp_moab, :status))
            expect(cv.results.contains_result_code?(AuditResults::UNEXPECTED_VERSION)).to be true
            expect(comp_moab.reload.status).to eq 'unexpected_version_on_storage'
          end
        end

        context 'moab_validation_errors indicates there are structural errors' do
          before do
            allow(moab_validator).to receive(:moab_validation_errors).and_return([{ Moab::StorageObjectValidator::MISSING_DIR => 'err msg' }])
          end

          [
            'ok',
            'online_moab_not_found',
            'unexpected_version_on_storage',
            'invalid_checksum',
            'validity_unknown'
          ].each do |initial_status|
            it "sets status as INVALID_MOAB_STATUS if it was #{initial_status}" do
              comp_moab.status = initial_status
              comp_moab.save!
              expect { cv.validate_checksums }.to change(comp_moab, :status).to 'invalid_moab'
              expect(comp_moab.reload.status).to eq 'invalid_moab'
            end
          end

          it 'leaves status as INVALID_MOAB_STATUS if complete moab started in that state' do
            comp_moab.invalid_moab!
            expect { cv.validate_checksums }.not_to(change(comp_moab, :status))
            expect(comp_moab.reload.status).to eq 'invalid_moab'
          end
        end
      end
    end

    context 'fails checksum validation' do
      it 'returns error codes for a comp_moab' do
        cv.validate_checksums
        expect(cv.results.result_array.first).to have_key(:file_not_in_manifest)
      end

      [
        'ok',
        'online_moab_not_found',
        'invalid_moab',
        'unexpected_version_on_storage',
        'validity_unknown'
      ].each do |initial_status|
        it "sets CompleteMoab status to INVALID_CHECKSUM_STATUS if it was initially #{initial_status}" do
          comp_moab.status = initial_status
          expect { cv.validate_checksums }.to change(comp_moab, :status).to 'invalid_checksum'
        end
      end

      it 'leaves CompleteMoab status as INVALID_CHECKSUM_STATUS if it already was' do
        comp_moab.status = 'invalid_checksum'
        expect { cv.validate_checksums }.not_to(change(comp_moab, :status))
      end

      context 'fails other moab validation' do
        context 'version on disk does not match expected version from catalog' do
          before do
            comp_moab.version = 4 # this is one greater than the version on disk for bz514sm9647
            comp_moab.save!
          end

          [
            'ok',
            'online_moab_not_found',
            'invalid_moab',
            'validity_unknown',
            'unexpected_version_on_storage'
          ].each do |initial_status|
            it "sets status to INVALID_CHECKSUM_STATUS if it was previously #{initial_status}" do
              comp_moab.status = initial_status
              comp_moab.save!
              expect { cv.validate_checksums }.to change(comp_moab, :status).to 'invalid_checksum'
              expect(comp_moab.reload.status).to eq 'invalid_checksum'
            end
          end

          it 'leaves status as INVALID_CHECKSUM_STATUS if complete moab started in that state' do
            comp_moab.invalid_checksum!
            expect { cv.validate_checksums }.not_to(change(comp_moab, :status))
            expect(comp_moab.reload.status).to eq 'invalid_checksum'
          end
        end

        context 'moab_validation_errors indicates there are structural errors' do
          before do
            allow(moab_validator).to receive(:moab_validation_errors).and_return([{ Moab::StorageObjectValidator::MISSING_DIR => 'err msg' }])
          end

          [
            'ok',
            'online_moab_not_found',
            'unexpected_version_on_storage',
            'validity_unknown',
            'invalid_moab'
          ].each do |initial_status|
            it "sets status as INVALID_CHECKSUM_STATUS if it was #{initial_status}" do
              comp_moab.status = initial_status
              comp_moab.save!
              expect { cv.validate_checksums }.to change(comp_moab, :status).to 'invalid_checksum'
              expect(comp_moab.reload.status).to eq 'invalid_checksum'
            end
          end

          it 'leaves status as INVALID_CHECKSUM_STATUS if complete moab started in that state' do
            comp_moab.invalid_checksum!
            expect { cv.validate_checksums }.not_to(change(comp_moab, :status))
            expect(comp_moab.reload.status).to eq 'invalid_checksum'
          end
        end
      end
    end

    context 'reports results ' do
      it 'calls AuditResults.report_results' do
        expect(cv.results).to receive(:report_results)
        cv.validate_checksums
      end
    end

    context 'deals with transactions properly' do
      let(:druid) { 'bz514sm9647' } # should pass validation
      let(:root_name) { 'fixture_sr1' }

      before do
        # would result in a status update if the save succeeded
        comp_moab.online_moab_not_found!

        # do this second since we save! as part of setup
        allow(comp_moab).to receive(:save!).and_raise(ActiveRecord::ConnectionTimeoutError)
      end

      it 'does not re-throw an ActiveRecord error we know how to deal with' do
        expect { cv.validate_checksums }.not_to raise_error
      end

      it 'has a result code indicating the update failed' do
        cv.validate_checksums
        expect(cv.results.contains_result_code?(AuditResults::DB_UPDATE_FAILED)).to eq true
      end

      it 'does not have a result code indicating the update happened' do
        cv.validate_checksums
        expect(cv.results.contains_result_code?(AuditResults::CM_STATUS_CHANGED)).to eq false
      end
    end
  end

  describe '#flag_unexpected_data_files' do
    let(:druid) { 'bj102hs9687' }
    let(:root_name) { 'fixture_sr1' }

    it 'calls validate_against_signature_catalog on each of the data_files' do
      # for easier reading, we assume data_files has a smaller return value
      files = ["#{object_dir}/v0001/data/metadata/contentMetadata.xml"]
      expect(cv).to receive(:data_files).and_return(files)
      allow(cv).to receive(:validate_against_signature_catalog)
      cv.send(:flag_unexpected_data_files)
      files.each do |file|
        expect(cv).to have_received(:validate_against_signature_catalog).with(file)
      end
      expect(cv).to have_received(:validate_against_signature_catalog).exactly(files.size).times
    end

    context 'files are on disk but not present in signatureCatalog.xml' do
      let(:druid) { 'zz555zz5555' }
      let(:root_name) { 'fixture_sr3' }

      before { allow(AuditResults).to receive(:new).and_return(results) }

      it 'adds a FILE_NOT_IN_SIGNATURE_CATALOG error' do
        content_file_path = "#{object_dir}/v0001/data/content/not_in_sigcat.txt"
        metadata_file_path = "#{object_dir}/v0001/data/metadata/also_not_in_sigcat.txt"
        nested_file_path = "#{object_dir}/v0001/data/content/unexpected/another_not_in_sigcat.txt"
        signature_catalog_path = "#{object_dir}/v0002/manifests/signatureCatalog.xml"
        expect(results).to receive(:add_result).with(
          AuditResults::FILE_NOT_IN_SIGNATURE_CATALOG, file_path: content_file_path, signature_catalog_path: signature_catalog_path
        )
        expect(results).to receive(:add_result).with(
          AuditResults::FILE_NOT_IN_SIGNATURE_CATALOG, file_path: metadata_file_path, signature_catalog_path: signature_catalog_path
        )
        expect(results).to receive(:add_result).with(
          AuditResults::FILE_NOT_IN_SIGNATURE_CATALOG, file_path: nested_file_path, signature_catalog_path: signature_catalog_path
        )
        cv.send(:flag_unexpected_data_files)
      end
    end
  end

  describe '#validate_signature_catalog' do
    let(:druid) { 'bj102hs9687' }
    let(:root_name) { 'fixture_sr1' }

    it 'calls validate_signature_catalog_listing' do
      expect(cv).to receive(:validate_signature_catalog_listing)
      cv.validate_signature_catalog
    end

    it 'calls flag_unexpected_data_content_files' do
      expect(cv).to receive(:flag_unexpected_data_files)
      cv.validate_signature_catalog
    end

    context 'file or directory does not exist' do
      let(:druid) { 'yy000yy0000' }
      let(:root_name) { 'fixture_sr2' }
      let(:results) { instance_double(AuditResults, report_results: nil) }

      it 'adds error code and continues executing' do
        allow(results).to receive(:add_result)
        allow(cv).to receive(:results).and_return(results)
        cv.validate_signature_catalog
        expect(results).to have_received(:add_result).with(
          AuditResults::SIGNATURE_CATALOG_NOT_IN_MOAB, anything
        ).at_least(:once)
      end
    end
  end

  context 'checksums are configurable' do
    it 'all three checksums at once' do
      allow(Moab::Config).to receive(:checksum_algos).and_return(%i[md5 sha1 sha256])
      expect(Digest::MD5).to receive(:new).and_call_original.at_least(:once)
      expect(Digest::SHA1).to receive(:new).and_call_original.at_least(:once)
      expect(Digest::SHA2).to receive(:new).and_call_original.at_least(:once)
      cv.validate_checksums
    end

    it 'defaults to md5 only' do
      expect(Digest::MD5).to receive(:new).and_call_original.at_least(:once)
      expect(Digest::SHA1).not_to receive(:new).and_call_original
      expect(Digest::SHA2).not_to receive(:new).and_call_original
      cv.validate_checksums
    end

    it 'sha256 only' do
      allow(Moab::Config).to receive(:checksum_algos).and_return([:sha256])
      expect(Digest::MD5).not_to receive(:new).and_call_original
      expect(Digest::SHA1).not_to receive(:new).and_call_original
      expect(Digest::SHA2).to receive(:new).and_call_original.at_least(:once)
      cv.validate_checksums
    end
  end

  context 'preservationAuditWF reporting' do
    let(:druid) { 'bz514sm9647' }
    let(:root_name) { 'fixture_sr1' }

    it 'has status changed to OK_STATUS and completes workflow' do
      comp_moab.invalid_moab!
      expect(workflow_reporter).to receive(:report_completed)
        .with(druid: druid,
              version: 3,
              check_name: 'validate_checksums',
              storage_area: ms_root,
              result: { cm_status_changed: 'CompleteMoab status changed from invalid_moab to ok' })
      cv.validate_checksums
    end

    it 'has status that does not change and does not complete workflow' do
      comp_moab.ok!
      expect(workflow_reporter).not_to receive(:report_completed)
      cv.validate_checksums
    end

    context 'has status changed to status other than OK_STATUS' do
      before do
        comp_moab.version = 4 # this is one greater than the version on disk for bz514sm9647
        comp_moab.save!
      end

      it 'does not complete workflow' do
        comp_moab.ok!
        expect(workflow_reporter).not_to receive(:report_completed)
        cv.validate_checksums
      end
    end

    context 'transaction is rolled back' do
      before do
        # would result in a status update if the save succeeded
        comp_moab.online_moab_not_found!

        # do this second since we save! as part of setup
        allow(comp_moab).to receive(:save!).and_raise(ActiveRecord::ConnectionTimeoutError)
      end

      it 'does not complete workflow' do
        expect(workflow_reporter).not_to receive(:report_completed)
        cv.validate_checksums
      end
    end
  end
end
