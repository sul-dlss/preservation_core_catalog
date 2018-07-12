require 'rails_helper'

RSpec.describe ArchivePreservedCopy, type: :model do
  let(:po) { build(:preserved_object) }
  let(:pc) { build(:preserved_copy) }
  let(:zip_endpoint) { build(:zip_endpoint) }
  let(:apc) { build(:archive_preserved_copy, preserved_copy: pc, zip_endpoint: zip_endpoint) }

  it 'is not valid without all required valid attributes' do
    expect(described_class.new).not_to be_valid
    expect(described_class.new(preserved_copy: pc)).not_to be_valid
    expect(apc).to be_valid
  end
  it { is_expected.to validate_presence_of(:zip_endpoint) }
  it { is_expected.to validate_presence_of(:preserved_copy) }
  it { is_expected.to validate_presence_of(:version) }

  it 'defines a status enum with the expected values' do
    is_expected.to define_enum_for(:status).with(
      'ok' => 0,
      'unreplicated' => 1,
      'archive_not_found' => 2,
      'invalid_checksum' => 3
    )
  end

  context '#status=' do
    it "validation rejects a value if it does not match the enum" do
      expect { described_class.new(status: 654) }
        .to raise_error(ArgumentError, "'654' is not a valid status")
      expect { described_class.new(status: 'INVALID_MOAB') }
        .to raise_error(ArgumentError, "'INVALID_MOAB' is not a valid status")
    end

    it "will accept a symbol, but will always return a string" do
      expect(described_class.new(status: :invalid_checksum).status).to eq 'invalid_checksum'
    end
  end

  it { is_expected.to belong_to(:preserved_copy) }
  it { is_expected.to belong_to(:zip_endpoint) }
  it { is_expected.to have_db_index(:zip_endpoint_id) }
  it { is_expected.to have_many(:zip_parts) }
  it { is_expected.to have_db_index(:last_existence_check) }
  it { is_expected.to have_db_index(:preserved_copy_id) }
  it { is_expected.to have_db_index(:status) }

end
