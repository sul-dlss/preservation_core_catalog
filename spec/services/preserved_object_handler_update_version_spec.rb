require 'rails_helper'
require 'services/shared_examples_preserved_object_handler'

RSpec.describe PreservedObjectHandler do
  let(:druid) { 'ab123cd4567' }
  let(:incoming_version) { 6 }
  let(:incoming_size) { 9876 }
  let!(:default_prez_policy) { PreservationPolicy.default_preservation_policy }
  let(:po) { PreservedObject.find_by(druid: druid) }
  let(:ep) { Endpoint.find_by(storage_location: 'spec/fixtures/storage_root01/moab_storage_trunk') }
  let(:pc) { PreservedCopy.find_by(preserved_object: po, endpoint: ep) }
  let(:exp_msg_prefix) { "PreservedObjectHandler(#{druid}, #{incoming_version}, #{incoming_size}, #{ep})" }
  let(:updated_status_msg_regex) { Regexp.new(Regexp.escape("#{exp_msg_prefix} PreservedCopy status changed from")) }
  let(:db_update_failed_prefix_regex_escaped) { Regexp.escape("#{exp_msg_prefix} db update failed") }
  let(:po_handler) { described_class.new(druid, incoming_version, incoming_size, ep) }

  describe '#update_version' do
    it_behaves_like 'attributes validated', :update_version

    context 'in Catalog' do
      before do
        po = PreservedObject.create!(druid: druid, current_version: 2, preservation_policy: default_prez_policy)
        @pc = PreservedCopy.create!(
          preserved_object: po, # TODO: see if we got the preserved object that we expected
          version: po.current_version,
          size: 1,
          endpoint: ep,
          status: Status.unexpected_version
        )
      end

      context 'incoming version newer than db versions (both) (happy path)' do
        let(:version_gt_pc_msg) { "#{exp_msg_prefix} incoming version (#{incoming_version}) greater than PreservedCopy db version" }
        let(:version_gt_po_msg) { "#{exp_msg_prefix} incoming version (#{incoming_version}) greater than PreservedObject db version" }
        let(:updated_pc_db_msg) { "#{exp_msg_prefix} PreservedCopy db object updated" }
        let(:updated_po_db_msg) { "#{exp_msg_prefix} PreservedObject db object updated" }

        it "updates entries with incoming version" do
          expect(pc.version).to eq 2
          expect(po.current_version).to eq 2
          po_handler.update_version
          expect(pc.reload.version).to eq incoming_version
          expect(po.reload.current_version).to eq incoming_version
        end
        it 'updates entries with size if included' do
          expect(pc.size).to eq 1
          po_handler.update_version
          expect(pc.reload.size).to eq incoming_size
        end
        it 'retains old size if incoming size is nil' do
          expect(pc.size).to eq 1
          po_handler = described_class.new(druid, incoming_version, nil, ep)
          po_handler.update_version
          expect(pc.reload.size).to eq 1
        end
        it 'updates status of PreservedCopy to "ok"' do
          expect(pc.status).to eq Status.unexpected_version
          po_handler.update_version
          expect(pc.reload.status).to eq Status.ok
        end
        it "logs at info level" do
          expect(Rails.logger).to receive(:log).with(Logger::INFO, version_gt_po_msg)
          expect(Rails.logger).to receive(:log).with(Logger::INFO, version_gt_pc_msg)
          expect(Rails.logger).to receive(:log).with(Logger::INFO, updated_po_db_msg)
          expect(Rails.logger).to receive(:log).with(Logger::INFO, updated_pc_db_msg)
          expect(Rails.logger).to receive(:log).with(Logger::INFO, updated_status_msg_regex)
          po_handler.update_version
        end

        context 'returns' do
          let!(:results) { po_handler.update_version }

          # results = [result1, result2]
          # result1 = {response_code: msg}
          # result2 = {response_code: msg}
          it '5 results' do
            expect(results).to be_an_instance_of Array
            expect(results.size).to eq 5
          end
          it 'ARG_VERSION_GREATER_THAN_DB_OBJECT results' do
            code = PreservedObjectHandler::ARG_VERSION_GREATER_THAN_DB_OBJECT
            expect(results).to include(a_hash_including(code => version_gt_pc_msg))
            expect(results).to include(a_hash_including(code => version_gt_po_msg))
          end
          it "UPDATED_DB_OBJECT results" do
            code = PreservedObjectHandler::UPDATED_DB_OBJECT
            expect(results).to include(a_hash_including(code => updated_pc_db_msg))
            expect(results).to include(a_hash_including(code => updated_po_db_msg))
          end
          it 'PC_STATUS_CHANGED result' do
            expect(results).to include(a_hash_including(PreservedObjectHandler::PC_STATUS_CHANGED => updated_status_msg_regex))
          end
        end
      end

      RSpec.shared_examples 'unexpected version' do |incoming_version|
        let(:po_handler) { described_class.new(druid, incoming_version, 1, ep) }
        let(:exp_msg_prefix) { "PreservedObjectHandler(#{druid}, #{incoming_version}, 1, #{ep})" }
        let(:version_msg_prefix) { "#{exp_msg_prefix} incoming version (#{incoming_version})" }
        let(:unexpected_version_msg) { "#{version_msg_prefix} has unexpected relationship to PreservedCopy db version; ERROR!" }
        let(:updated_po_db_timestamp_msg) { "#{exp_msg_prefix} PreservedObject updated db timestamp only" }
        let(:updated_pc_db_timestamp_msg) { "#{exp_msg_prefix} PreservedCopy updated db timestamp only" }

        it "entry version stays the same" do
          pocv = po.current_version
          pcv = pc.version
          po_handler.update_version
          expect(po.reload.current_version).to eq pocv
          expect(pc.reload.version).to eq pcv
        end
        it "entry size stays the same" do
          expect(pc.size).to eq 1
          po_handler.update_version
          expect(pc.reload.size).to eq 1
        end
        it 'updates status of PreservedCopy to "ok"' do
          skip("should it update status of PreservedCopy?")
          expect(pc.status).to eq Status.unexpected_version
          po_handler.update_version
          expect(pc.reload.status).to eq Status.ok
        end
        it "logs at error level" do
          expect(Rails.logger).to receive(:log).with(Logger::ERROR, unexpected_version_msg)
          skip("should it have status msg change? timestamp change?")
          # expect(Rails.logger).to receive(:log).with(Logger::INFO, updated_pc_db_timestamp_msg)
          # expect(Rails.logger).to receive(:log).with(Logger::ERROR, updated_po_db_timestamp_msg)
          # expect(Rails.logger).to receive(:log).with(Logger::INFO, updated_status_msg_regex)
          po_handler.update_version
        end

        context 'returns' do
          let!(:results) { po_handler.update_version }

          # results = [result1, result2]
          # result1 = {response_code: msg}
          # result2 = {response_code: msg}
          it '3 results' do
            expect(results).to be_an_instance_of Array
            expect(results.size).to eq 3
          end
          it 'UNEXPECTED_VERSION result' do
            code = PreservedObjectHandler::UNEXPECTED_VERSION
            expect(results).to include(a_hash_including(code => unexpected_version_msg))
          end
          it 'specific version results' do
            codes = [
              PreservedObjectHandler::VERSION_MATCHES,
              PreservedObjectHandler::ARG_VERSION_GREATER_THAN_DB_OBJECT,
              PreservedObjectHandler::ARG_VERSION_LESS_THAN_DB_OBJECT
            ]
            obj_version_results = results.select { |r| codes.include?(r.keys.first) }
            msgs = obj_version_results.map { |r| r.values.first }
            expect(msgs).to include(a_string_matching("PreservedObject"))
            expect(msgs).to include(a_string_matching("PreservedCopy"))
          end
          it "UPDATED_DB_OBJECT_TIMESTAMP_ONLY results" do
            skip("should it have a timestamp change?")
            code = PreservedObjectHandler::UPDATED_DB_OBJECT
            expect(results).to include(a_hash_including(code => updated_pc_db_timestamp_msg))
            expect(results).to include(a_hash_including(code => updated_po_db_timestamp_msg))
          end
          it 'PC_STATUS_CHANGED result' do
            skip("should it have status msg change?")
            expect(results).to include(a_hash_including(PreservedObjectHandler::PC_STATUS_CHANGED => updated_status_msg_regex))
          end
        end
      end

      context 'PreservedCopy and PreservedObject versions do not match' do
        before do
          @pc.version = @pc.version + 1
          @pc.save
        end

        it_behaves_like 'unexpected version', 8
      end

      context 'incoming version same as db versions (both)' do
        it_behaves_like 'unexpected version', 2
      end

      context 'incoming version lower than db versions (both)' do
        it_behaves_like 'unexpected version', 1
      end

      context 'db update error' do
        let(:result_code) { PreservedObjectHandler::DB_UPDATE_FAILED }

        context 'PreservedCopy' do
          context 'ActiveRecordError' do
            let(:results) do
              allow(Rails.logger).to receive(:log)
              # FIXME: couldn't figure out how to put next line into its own test
              expect(Rails.logger).to receive(:log).with(Logger::ERROR, /#{db_update_failed_prefix_regex_escaped}/)

              po = instance_double('PreservedObject')
              allow(po).to receive(:current_version).and_return(1)
              allow(PreservedObject).to receive(:find_by!).with(druid: druid).and_return(po)
              pc = instance_double('PreservedCopy')
              allow(PreservedCopy).to receive(:find_by!).with(preserved_object: po, endpoint: ep).and_return(pc)
              allow(pc).to receive(:version).and_return(1)
              allow(pc).to receive(:version=)
              allow(pc).to receive(:changed?).and_return(true)
              allow(pc).to receive(:save!).and_raise(ActiveRecord::ActiveRecordError, 'foo')
              status = instance_double('Status')
              allow(status).to receive(:status_text)
              allow(pc).to receive(:status).and_return(status)
              allow(pc).to receive(:status=)
              allow(pc).to receive(:size=)
              po_handler.update_version
            end

            context 'DB_UPDATE_FAILED error' do
              it 'prefix' do
                expect(results).to include(a_hash_including(result_code => a_string_matching(db_update_failed_prefix_regex_escaped)))
              end
              it 'specific exception raised' do
                expect(results).to include(a_hash_including(result_code => a_string_matching('ActiveRecord::ActiveRecordError')))
              end
              it "exception's message" do
                expect(results).to include(a_hash_including(result_code => a_string_matching('foo')))
              end
            end
          end
        end
        context 'PreservedObject' do
          context 'ActiveRecordError' do
            let(:results) do
              allow(Rails.logger).to receive(:log)
              # FIXME: couldn't figure out how to put next line into its own test
              expect(Rails.logger).to receive(:log).with(Logger::ERROR, /#{db_update_failed_prefix_regex_escaped}/)

              po = instance_double('PreservedObject')
              allow(po).to receive(:current_version).and_return(5)
              allow(po).to receive(:current_version=).with(incoming_version)
              allow(po).to receive(:changed?).and_return(true)
              allow(po).to receive(:save!).and_raise(ActiveRecord::ActiveRecordError, 'foo')
              allow(PreservedObject).to receive(:find_by).with(druid: druid).and_return(po)
              pc = instance_double('PreservedCopy')
              allow(PreservedCopy).to receive(:find_by).with(preserved_object: po, endpoint: ep).and_return(pc)
              allow(pc).to receive(:version).and_return(5)
              allow(pc).to receive(:version=).with(incoming_version)
              allow(pc).to receive(:size=).with(incoming_size)
              allow(pc).to receive(:changed?).and_return(true)
              allow(pc).to receive(:save!)
              status = instance_double('Status')
              allow(status).to receive(:status_text)
              allow(pc).to receive(:status).and_return(status)
              allow(pc).to receive(:status=)
              po_handler.update_version
            end

            context 'DB_UPDATE_FAILED error' do
              it 'prefix' do
                expect(results).to include(a_hash_including(result_code => a_string_matching(db_update_failed_prefix_regex_escaped)))
              end
              it 'specific exception raised' do
                expect(results).to include(a_hash_including(result_code => a_string_matching('ActiveRecord::ActiveRecordError')))
              end
              it "exception's message" do
                expect(results).to include(a_hash_including(result_code => a_string_matching('foo')))
              end
            end
          end
        end
      end

      it 'calls PreservedObject.save! and PreservedCopy.save! if the existing record is altered' do
        po = instance_double(PreservedObject)
        pc = instance_double(PreservedCopy)
        allow(PreservedObject).to receive(:find_by).with(druid: druid).and_return(po)
        allow(po).to receive(:current_version).and_return(1)
        allow(po).to receive(:current_version=).with(incoming_version)
        allow(po).to receive(:changed?).and_return(true)
        allow(po).to receive(:save!)
        allow(PreservedCopy).to receive(:find_by).with(preserved_object: po, endpoint: ep).and_return(pc)
        allow(pc).to receive(:version).and_return(1)
        allow(pc).to receive(:version=).with(incoming_version)
        allow(pc).to receive(:size=).with(incoming_size)
        allow(pc).to receive(:endpoint).with(ep)
        allow(pc).to receive(:changed?).and_return(true)
        allow(pc).to receive(:status).and_return(instance_double(Status, status_text: 'ok'))
        allow(pc).to receive(:status=)
        allow(pc).to receive(:save!)
        po_handler.update_version
        expect(po).to have_received(:save!)
        expect(pc).to have_received(:save!)
      end

      it 'calls PreservedObject.touch and PreservedCopy.touch if the existing record is NOT altered' do
        skip('need to determine if we want to update timestamps in this situation')
        po_handler = described_class.new(druid, 1, 1, ep)
        po = instance_double(PreservedObject)
        pc = instance_double(PreservedCopy)
        allow(PreservedObject).to receive(:find_by).with(druid: druid).and_return(po)
        allow(po).to receive(:current_version).and_return(1)
        allow(po).to receive(:changed?).and_return(false)
        allow(po).to receive(:touch)
        allow(PreservedCopy).to receive(:find_by).with(preserved_object: po, endpoint: ep).and_return(pc)
        allow(pc).to receive(:version).and_return(1)
        allow(pc).to receive(:endpoint).with(ep)
        allow(pc).to receive(:changed?).and_return(false)
        allow(pc).to receive(:touch)
        po_handler.update_version
        expect(po).to have_received(:touch)
        expect(pc).to have_received(:touch)
      end

      it 'logs a debug message' do
        msg = "update_version #{druid} called"
        allow(Rails.logger).to receive(:debug)
        po_handler.update_version
        expect(Rails.logger).to have_received(:debug).with(msg)
      end
    end

    it_behaves_like 'druid not in catalog', :update_version

    it_behaves_like 'PreservedCopy does not exist', :update_version
  end

end
