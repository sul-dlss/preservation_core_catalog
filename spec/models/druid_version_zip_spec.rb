require 'rails_helper'

describe DruidVersionZip do
  let(:dvz) { described_class.new(druid, version) }
  let(:druid) { 'bj102hs9687' }
  let(:version) { 1 }

  describe '#s3_key' do
    it 'returns a tree path-based key' do
      expect(dvz.s3_key).to eq 'bj/102/hs/9687/bj102hs9687.v0001.zip'
    end
  end

  describe '#file_path' do
    it 'returns a full path' do
      expect(dvz.file_path).to eq '/tmp/bj/102/hs/9687/bj102hs9687.v0001.zip'
    end
  end

  describe '#create_zip!' do
    let(:zip_path) { dvz.file_path }
    let(:version) { 3 } # v1 and v2 pre-existing

    after { FileUtils.rm_rf('/tmp/bj') } # cleanup

    context 'succeeds in zipping the binary' do
      after { File.delete(zip_path) }

      it 'produces the expected zip file' do
        expect(File).not_to exist(zip_path)
        expect { dvz.create_zip! }.not_to raise_error
        expect(File).to exist(zip_path)
      end

      # we `list` a given filepath out of the zip, `unzip` exits w/ 0 only when found
      it 'produced zip has expected structure' do
        techmd = "bj102hs9687/v0003/data/metadata/technicalMetadata.xml"
        dvz.create_zip!
        _, status = Open3.capture2e("unzip -lq #{zip_path} #{techmd}")
        expect(status).to be_success
        _, status = Open3.capture2e("unzip -lq #{zip_path} bj/102/hs/9687/#{techmd}")
        expect(status).not_to be_success
      end
    end

    context 'fails to zip the binary' do
      before { allow(dvz).to receive(:zip_command).and_return(zip_command) }

      context 'when inpath is incorrect' do
        let(:zip_command) { "zip -r0X -s 10g #{zip_path} /wrong/path" }

        it 'raises error' do
          expect { dvz.create_zip! }.to raise_error(RuntimeError, %r{zipmaker failure.*/wrong/path}m)
        end
      end

      context 'when options are unsupported' do
        let(:zip_command) { "zip --fantasy #{zip_path} #{druid}/v0003" }

        it 'raises error' do
          expect { dvz.create_zip! }.to raise_error(RuntimeError, /Invalid command arguments.*fantasy/)
        end
      end

      context 'if the utility "moved"' do
        let(:zip_command) { "zap -r0X -s 10g #{zip_path} #{druid}/v0003" }

        it 'raises error' do
          expect { dvz.create_zip! }.to raise_error(Errno::ENOENT, /No such file/)
        end
      end
    end
  end

  describe '#expected_part_keys' do
    it 'raises for invalid integer' do
      expect { dvz.expected_part_keys(0) }.to raise_error ArgumentError
    end
    it 'lists the files expected' do
      expect(dvz.expected_part_keys(1)).to eq ['bj/102/hs/9687/bj102hs9687.v0001.zip']
      expect(dvz.expected_part_keys(2)).to eq [
        'bj/102/hs/9687/bj102hs9687.v0001.zip',
        'bj/102/hs/9687/bj102hs9687.v0001.z01'
      ]
      one_oh_one = dvz.expected_part_keys(101)
      expect(one_oh_one.count).to eq(101)
      expect(one_oh_one.last).to eq('bj/102/hs/9687/bj102hs9687.v0001.z100')
    end
  end

  describe '#hex_to_base64' do
    it 'returns base64-encoded value' do
      expect(dvz.hex_to_base64('4f98f59e877ecb84ff75ef0fab45bac5')).to eq 'T5j1nod+y4T/de8Pq0W6xQ=='
      expect(dvz.hex_to_base64('d41d8cd98f00b204e9800998ecf8427e')).to eq '1B2M2Y8AsgTpgAmY7PhCfg=='
    end
  end

  describe '#moab_version_path' do
    it 'returns authoritative file location' do
      expect(dvz.moab_version_path)
        .to eq 'spec/fixtures/storage_root01/sdr2objects/bj/102/hs/9687/bj102hs9687/v0001'
    end
  end

  describe '#part_keys' do
    let(:druid) { 'dc048cw1328' }

    before do
      FileUtils.rm_rf('/tmp/dc') # prep dir
      dvz.ensure_zip_directory!
      %w[zip z01 z02 z03 z04].each do |f|
        FileUtils.touch("/tmp/dc/048/cw/1328/dc048cw1328.v0001.#{f}")
      end
    end
    after { FileUtils.rm_rf('/tmp/dc') } # cleanup

    it 'lists the multiple files produced' do
      expect(dvz.part_keys).to all(be_a String)
      expect(dvz.part_keys).to include(
        "dc/048/cw/1328/dc048cw1328.v0001.zip",
        "dc/048/cw/1328/dc048cw1328.v0001.z01",
        "dc/048/cw/1328/dc048cw1328.v0001.z02",
        "dc/048/cw/1328/dc048cw1328.v0001.z03",
        "dc/048/cw/1328/dc048cw1328.v0001.z04"
      )
      expect(dvz.part_keys.count).to eq 5
    end
  end

  describe '#part_paths' do # zip splits
    let(:druid) { 'dc048cw1328' } # fixture is 4.9 MB

    before do
      allow(dvz).to receive(:zip_split_size).and_return('1m')
      FileUtils.rm_rf('/tmp/dc') # prep clean dir
    end
    after { FileUtils.rm_rf('/tmp/dc') } # cleanup

    it 'lists the multiple files produced' do
      dvz.create_zip!
      expect(dvz.part_paths).to all(be_a Pathname)
      expect(dvz.part_paths.map(&:to_s)).to include(
        "/tmp/dc/048/cw/1328/dc048cw1328.v0001.zip",
        "/tmp/dc/048/cw/1328/dc048cw1328.v0001.z01",
        "/tmp/dc/048/cw/1328/dc048cw1328.v0001.z04"
      )
      expect(dvz.part_paths.count).to eq 5
    end
  end

  describe '#zip_command' do
    let(:zip_path) { '/tmp/bj/102/hs/9687/bj102hs9687.v0001.zip' }

    it 'returns zip string to execute for this druid/version' do
      expect(dvz.zip_command).to eq "zip -r0X -s 10g #{zip_path} bj102hs9687/v0001"
    end
  end

  describe '#zip_version' do
    it 'calls fetch_zip_version only once' do
      dvz.zip_version
      expect(dvz).not_to receive(:fetch_zip_version)
      dvz.zip_version
    end
  end

  describe '#zip_version_regexp' do
    subject { dvz.send(:zip_version_regexp) }

    it { is_expected.to match('This is Zip 3.0 (July 5th 2008), by Info-ZIP.') }
    it { is_expected.to match('This is Zip 5.0.2 (April 19th 2021), by Cyberdyne II') }
    it { is_expected.not_to match(%[Copyright (c) 1990-2008 Info-ZIP - Type 'zip "-L"' for software license.]) }
    it { is_expected.not_to match('bzip2, a block-sorting file compressor.  Version 1.0.6, 6-Sept-2010.') }
  end

  describe '#fetch_zip_version' do
    it 'gets version from the system zip' do
      expect(dvz.send(:fetch_zip_version)).to match(/^Zip \d+\.\d+/)
    end
  end
end
