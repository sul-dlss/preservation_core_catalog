# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MoabStorageService do
  let(:druid) { 'jj925bx9565' }

  describe '.content_diff' do
    let(:subset) { 'all' }
    let(:version) { nil }
    let(:content_md) { '<contentMetadata>yer stuff here</contentMetadata>' }
    let(:result) { Stanford::StorageServices.compare_cm_to_version(content_md, druid, 'all', 1) }

    it 'calls Stanford::StorageServices.compare_cm_to_version' do
      allow(Stanford::StorageServices).to receive(:compare_cm_to_version).with(content_md, druid, 'all', version).and_return(result)
      expect(described_class.content_diff(druid, content_md)).to eq result
      expect(Stanford::StorageServices).to have_received(:compare_cm_to_version).with(content_md, druid, 'all', nil)
    end

    context 'when moab-versioning gem raises error' do
      it 'passes along error' do
        emsg = 'my error'
        allow(Stanford::StorageServices).to receive(:compare_cm_to_version)
          .with(content_md, druid, 'all', version)
          .and_raise(Moab::InvalidMetadataException, emsg)
        expect { described_class.content_diff(druid, content_md) }.to raise_error(Moab::InvalidMetadataException, emsg)
      end
    end

    context 'content_md param' do
      let(:err_msg) { 'No contentMetadata provided to MoabStorageService.content_diff for druid jj925bx9565' }

      context 'when missing' do
        it 'raises ArgumentError' do
          expect { described_class.content_diff(druid, nil) }.to raise_error(ArgumentError, err_msg)
        end
      end

      context 'when empty' do
        it 'raises ArgumentError' do
          expect { described_class.content_diff(druid, '') }.to raise_error(ArgumentError, err_msg)
        end
      end
    end

    context 'subset param' do
      let(:err_msg) { "subset arg must be 'all', 'shelve', 'preserve', or 'publish' (MoabStorageService.content_diff for druid jj925bx9565)" }

      before do
        allow(Stanford::StorageServices).to receive(:compare_cm_to_version).with(content_md, druid, subset, version).and_return(result)
      end

      context 'when all' do
        let(:subset) { 'all' }

        it 'returns the requested filepath' do
          expect(described_class.content_diff(druid, content_md, subset)).to eq result
        end
      end

      context 'when shelve' do
        let(:subset) { 'shelve' }

        it 'returns the requested filepath' do
          expect(described_class.content_diff(druid, content_md, subset)).to eq result
        end
      end

      context 'when preserve' do
        let(:subset) { 'preserve' }

        it 'returns the requested filepath' do
          expect(described_class.content_diff(druid, content_md, subset)).to eq result
        end
      end

      context 'when publish' do
        let(:subset) { 'publish' }

        it 'returns the requested filepath' do
          expect(described_class.content_diff(druid, content_md, subset)).to eq result
        end
      end

      context 'when unrecognized value' do
        let(:subset) { 'unrecognized' }

        it 'raises ArgumentError' do
          expect { described_class.content_diff(druid, content_md, subset) }.to raise_error(ArgumentError, err_msg)
        end
      end

      context 'when explicitly set to nil' do
        it 'raises ArgumentError' do
          expect { described_class.content_diff(druid, content_md, nil) }.to raise_error(ArgumentError, err_msg)
        end
      end
    end

    context 'version param' do
      context 'when specified correctly' do
        it 'returns the requested FileInventoryDifference' do
          expect(described_class.content_diff(druid, content_md, subset, 1)).to be_an_instance_of Moab::FileInventoryDifference
        end
      end

      context 'when not a positive integer value' do
        it 'raises Moab::MoabRuntimeError' do
          err_msg = 'Version ID v3 does not exist'
          expect { described_class.content_diff(druid, content_md, subset, 'v3') }.to raise_error(Moab::MoabRuntimeError, err_msg)
        end
      end

      context 'when too high a version' do
        it 'raises Moab::MoabRuntimeError' do
          err_msg = 'Version ID 666 does not exist'
          expect { described_class.content_diff(druid, content_md, subset, 666) }.to raise_error(Moab::MoabRuntimeError, err_msg)
        end
      end

      context 'when missing' do
        it 'uses the most recent version and returns the requested FileInventoryDifference' do
          # FIXME: this is not checking for most recent version!
          expect(described_class.content_diff(druid, content_md)).to be_an_instance_of Moab::FileInventoryDifference
        end
      end
    end
  end

  describe '.filepath' do
    let(:logger_double) { instance_double(Logger, info: nil, error: nil, add: nil) }

    before do
      allow(Audit::MoabToCatalog).to receive(:logger).and_return(logger_double)
      Audit::MoabToCatalog.check_existence_for_druid(druid)
    end

    context 'when file is not in Moab' do
      it 'passes along error raised by moab-versioning gem' do
        emsg = 'content file foobar not found for druid:jj925bx9565 - 2'
        expect { described_class.filepath(druid, 'content', 'foobar') }.to raise_error(Moab::FileNotFoundException, emsg)
      end
    end

    describe 'category param:' do
      let(:err_msg) { "category arg must be 'content', 'metadata', or 'manifest' (MoabStorageService.filepath for druid jj925bx9565)" }

      context 'when manifest' do
        let(:category) { 'manifest' }
        let(:fname) { 'versionAdditions.xml' }
        let(:file_path) do
          Pathname.new('spec/fixtures/storage_root01/sdr2objects/jj/925/bx/9565/jj925bx9565/v0002/manifests/versionAdditions.xml')
        end

        it 'returns the requested filepath' do
          expect(described_class.filepath(druid, category, fname)).to eq file_path
        end
      end

      context 'when metadata' do
        let(:category) { 'metadata' }
        let(:fname) { 'identityMetadata.xml' }
        let(:file_path) do
          # NOTE: this file was not modified in v2, so we get the path to v1's copy
          Pathname.new('spec/fixtures/storage_root01/sdr2objects/jj/925/bx/9565/jj925bx9565/v0001/data/metadata/identityMetadata.xml')
        end

        it 'returns the requested filepath' do
          expect(described_class.filepath(druid, category, fname)).to eq file_path
        end
      end

      context 'when content' do
        let(:category) { 'content' }
        let(:fname) { 'PC0170_s3_4th_of_July_2010-07-04_095432_0003.jpg' }
        let(:file_path) do
          # NOTE: this file was not modified in v2, so we get the path to v1's copy
          Pathname.new(
            'spec/fixtures/storage_root01/sdr2objects/jj/925/bx/9565/jj925bx9565/v0001/data/content/PC0170_s3_4th_of_July_2010-07-04_095432_0003.jpg'
          )
        end

        # TODO: still fails even after adding druid to catalog
        it 'returns the requested filepath' do
          expect(described_class.filepath(druid, category, fname)).to eq file_path
        end
      end

      context 'when unrecognized value' do
        let(:category) { 'unrecognized' }

        it 'raises ArgumentError' do
          expect { described_class.filepath(druid, category, 'foo') }.to raise_error(ArgumentError, err_msg)
        end
      end

      context 'when missing' do
        it 'raises ArgumentError' do
          expect { described_class.filepath(druid, nil, 'filename') }.to raise_error(ArgumentError, err_msg)
        end
      end
    end

    describe 'filename param' do
      context 'when missing' do
        let(:err_msg) { 'No filename provided to MoabStorageService.filepath for druid jj925bx9565' }

        it 'raises ArgumentError' do
          expect { described_class.filepath(druid, 'metadata', nil) }.to raise_error(ArgumentError, err_msg)
        end
      end
    end

    describe 'version param' do
      context 'when specified correctly' do
        let(:exp_pathname) do
          Pathname.new('spec/fixtures/storage_root01/sdr2objects/jj/925/bx/9565/jj925bx9565/v0001/manifests/manifestInventory.xml')
        end

        it 'returns the requested filepath' do
          expect(described_class.filepath(druid, 'manifest', 'manifestInventory.xml', 1)).to eq exp_pathname
        end
      end

      context 'when not a positive integer value' do
        it 'raises Moab::MoabRuntimeError' do
          err_msg = 'Version ID v3 does not exist'
          expect { described_class.filepath(druid, 'metadata', 'identityMetadata.xml', 'v3') }.to raise_error(Moab::MoabRuntimeError, err_msg)
        end
      end

      context 'when too high a version' do
        it 'raises Moab::MoabRuntimeError' do
          err_msg = 'Version ID 666 does not exist'
          expect { described_class.filepath(druid, 'metadata', 'identityMetadata.xml', 666) }.to raise_error(Moab::MoabRuntimeError, err_msg)
        end
      end

      context 'when missing' do
        let(:exp_pathname) do
          Pathname.new('spec/fixtures/storage_root01/sdr2objects/jj/925/bx/9565/jj925bx9565/v0002/manifests/manifestInventory.xml')
        end

        it 'returns the most recent version' do
          expect(described_class.filepath(druid, 'manifest', 'manifestInventory.xml')).to eq exp_pathname
        end
      end
    end
  end

  describe '.retrieve_content_file_group' do
    it 'calls Moab::StorageServices.retrieve_file_group for "content"' do
      allow(Moab::StorageServices).to receive(:retrieve_file_group).with('content', druid)
      described_class.retrieve_content_file_group(druid)
      expect(Moab::StorageServices).to have_received(:retrieve_file_group).with('content', druid)
    end
  end
end
