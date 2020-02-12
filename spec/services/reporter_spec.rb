# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reporter do
  let!(:test_start_time) { DateTime.now.utc.iso8601 } # useful for both output cleanup and CSV filename testing

  let!(:msr_a) { create(:moab_storage_root) }
  let!(:complete_moab_1) { create(:complete_moab, moab_storage_root: msr_a) }
  let!(:complete_moab_2) { create(:complete_moab, moab_storage_root: msr_a) }
  let!(:complete_moab_3) { create(:complete_moab, moab_storage_root: msr_a) }

  let(:reporter) { described_class.new(storage_root_name: msr_a.name) }

  describe '#druid_csv_list' do
    let(:druid_csv_list) {
      [[complete_moab_1.preserved_object.druid],
       [complete_moab_2.preserved_object.druid],
       [complete_moab_3.preserved_object.druid]]
    }

    it 'returns a list of druids on a storage_root' do
      expect(reporter.druid_csv_list).to eq(druid_csv_list)
    end
  end

  describe '#moab_detail_csv_list' do
    let(:moab_detail_csv_list) {
      [complete_moab_1, complete_moab_2, complete_moab_3].map do |cm|
        [cm.preserved_object.druid, nil, cm.moab_storage_root.name, nil, nil, 'ok', nil]
      end
    }

    it 'returns a hash of values for the given moab' do
      expect(reporter.moab_detail_csv_list).to eq(moab_detail_csv_list)
    end
  end

  describe '#write_to_csv' do
    let(:moab_detail) {
      [['test_val1', 'test_val2', nil, nil, 'ok', nil, 'another value']]
    }

    after do
      next unless FileTest.exist?(reporter.default_filepath)
      Dir.each_child(reporter.default_filepath) do |filename|
        fullpath_filename = File.join(reporter.default_filepath, filename)
        File.unlink(fullpath_filename) if File.stat(fullpath_filename).mtime > test_start_time
      end
    end

    it 'creates a default file containing a list of druids from the given storage root' do
      csv_filename = reporter.write_to_csv(moab_detail, report_type: 'test')
      expect(CSV.read(csv_filename)).to eq([['test_val1', 'test_val2', nil, nil, 'ok', nil, 'another value']])
      expect(csv_filename).to match(%r{^#{reporter.default_filepath}\/MoabStorageRoot_#{msr_a.name}_test_.*\.csv$})
      timestamp_str = /MoabStorageRoot_#{msr_a.name}_test_(.*)\.csv$/.match(csv_filename).captures[0]
      expect(DateTime.parse(timestamp_str)).to be >= test_start_time
    end

    it 'allows the caller to specify an alternate filename, including full path' do
      alternate_filename = '/tmp/my_cool_druid_export.csv'
      csv_filename = reporter.write_to_csv(moab_detail, filename: alternate_filename)
      expect(csv_filename).to eq(alternate_filename)
      expect(CSV.read(csv_filename)).to eq([['test_val1', 'test_val2', nil, nil, 'ok', nil, 'another value']])
    ensure
      File.unlink(alternate_filename) if FileTest.exist?(alternate_filename)
    end

    it 'lets the DB error bubble up if the given storage root does not exist' do
      expect { described_class.new(storage_root_name: 'nonexistent') }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'raises an error if the intended file name is already in use' do
      duplicated_filename = File.join(reporter.default_filepath, 'my_duplicated_filename.csv')
      reporter.write_to_csv(moab_detail, filename: duplicated_filename)
      expect {
        reporter.write_to_csv(moab_detail, filename: duplicated_filename)
      }.to raise_error(StandardError, "#{duplicated_filename} already exists, aborting!")
    end

    it 'raises an ArgumentError if caller provides neither report_type nor filename' do
      expect { reporter.write_to_csv(csv_lines) }.to raise_error(ArgumentError, 'Must specify at least one of report_type or filename')
    end
  end
end
