# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CompleteMoab, type: :model do
  let(:druid) { 'ab123cd4567' }
  let(:preserved_object) { create(:preserved_object, druid: druid) }
  let(:status) { 'validity_unknown' }
  let(:cm_version) { 1 }
  let(:args) do # default constructor params
    {
      preserved_object: preserved_object,
      version: cm_version,
      status: status
    }
  end

  # some tests assume the PC and PO exist before the vars are referenced.  the eager instantiation of cm will cause
  # instantiation of preserved_object, since cm depends on it (via args).
  let!(:cm) { create(:complete_moab, args) }
  let(:now) { Time.now.utc }

  it 'is not valid without all required valid attributes' do
    expect(described_class.new).not_to be_valid
    expect(described_class.new(preserved_object_id: preserved_object.id)).not_to be_valid
    expect(described_class.new(args.merge(moab_storage_root_id: MoabStorageRoot.first.id, size: 1))).to be_valid
  end

  it 'defines a status enum with the expected values' do
    is_expected.to define_enum_for(:status).with_values(
      'ok' => 0,
      'invalid_moab' => 1,
      'invalid_checksum' => 2,
      'online_moab_not_found' => 3,
      'unexpected_version_on_storage' => 4,
      'validity_unknown' => 6
    )
  end

  describe '#status=' do
    it 'validation rejects a value if it does not match the enum' do
      expect { described_class.new(status: 654) }
        .to raise_error(ArgumentError, "'654' is not a valid status")
      expect { described_class.new(status: 'INVALID_MOAB') }
        .to raise_error(ArgumentError, "'INVALID_MOAB' is not a valid status")
    end

    it 'will accept a symbol, but will always return a string' do
      expect(described_class.new(status: :invalid_moab).status).to eq 'invalid_moab'
    end
  end

  describe '#replicatable_status?' do
    it 'reponds true IFF status should allow replication' do
      # validity_unknown initial status implicitly tested (otherwise assignment wouldn't change the reponse)
      expect { cm.status = 'ok'                            }.to change(cm, :replicatable_status?).to(true)
      expect { cm.status = 'invalid_checksum'              }.to change(cm, :replicatable_status?).to(false)
      expect { cm.status = 'invalid_moab'                  }.not_to change(cm, :replicatable_status?).from(false)
      expect { cm.status = 'online_moab_not_found'         }.not_to change(cm, :replicatable_status?).from(false)
      expect { cm.status = 'unexpected_version_on_storage' }.not_to change(cm, :replicatable_status?).from(false)
    end
  end

  it { is_expected.to belong_to(:moab_storage_root) }
  it { is_expected.to belong_to(:preserved_object) }
  it { is_expected.to have_db_index(:last_version_audit) }
  it { is_expected.to have_db_index(:last_moab_validation) }
  it { is_expected.to have_db_index(:last_checksum_validation) }
  it { is_expected.to have_db_index(:moab_storage_root_id) }
  it { is_expected.to have_db_index(:preserved_object_id) }
  it { is_expected.to validate_presence_of(:moab_storage_root) }
  it { is_expected.to validate_presence_of(:preserved_object) }
  it { is_expected.to validate_presence_of(:version) }
  it { is_expected.to validate_uniqueness_of(:preserved_object_id).scoped_to(:moab_storage_root_id) }

  describe '#validate_checksums!' do
    it 'passes self to ChecksumValidationJob' do
      expect(ChecksumValidationJob).to receive(:perform_later).with(cm)
      cm.validate_checksums!
    end
  end

  describe '#update_audit_timestamps' do
    it 'updates last_moab_validation time if moab_validated is true' do
      expect { cm.update_audit_timestamps(true, false) }.to change(cm, :last_moab_validation).from(nil)
    end

    it 'does not update last_moab_validation time if moab_validated is false' do
      expect { cm.update_audit_timestamps(false, false) }.not_to change(cm, :last_moab_validation).from(nil)
    end

    it 'updates last_version_audit time if version_audited is true' do
      expect { cm.update_audit_timestamps(false, true) }.to change(cm, :last_version_audit).from(nil)
    end

    it 'does not update last_version_audit time if version_audited is false' do
      expect { cm.update_audit_timestamps(false, false) }.not_to change(cm, :last_version_audit).from(nil)
    end
  end

  describe '#upd_audstamps_version_size' do
    it 'updates version' do
      expect { cm.upd_audstamps_version_size(false, 3, nil) }.to change(cm, :version).to(3)
    end

    it 'updates size if size is not nil' do
      expect { cm.upd_audstamps_version_size(false, 0, 123) }.to change(cm, :size).to(123)
    end

    it 'does not update size if size is nil' do
      expect { cm.upd_audstamps_version_size(false, 0, nil) }.not_to change(cm, :size)
    end

    it 'calls update_audit_timestamps with the appropriate params' do
      expect(cm).to receive(:update_audit_timestamps).with(false, true)
      cm.upd_audstamps_version_size(false, 3, nil)
    end
  end

  describe '#matches_po_current_version?' do
    before { cm.version = 666 }

    it 'returns true when its version matches its preserved objects current version' do
      cm.preserved_object.current_version = 666
      expect(cm.matches_po_current_version?).to be true
    end

    it 'returns false when its version does not match its preserved objects current version' do
      cm.preserved_object.current_version = 777
      expect(cm.matches_po_current_version?).to be false
    end
  end

  describe '#migrate_moab' do
    let(:target_storage_root) { create(:moab_storage_root) }
    let(:yesterday) { now - 1.day }
    let(:cm) do
      # pretend we're moving a nice recently validated moab
      create(
        :complete_moab,
        args.merge(
          status: 'ok',
          status_details: 'status now ok',
          last_moab_validation: yesterday,
          last_checksum_validation: yesterday,
          last_version_audit: yesterday
        )
      )
    end

    it 'updates the current storage root, records the old one, and clears audit info' do
      expect(cm.from_moab_storage_root).to be_nil
      orig_storage_root = cm.moab_storage_root

      cm.migrate_moab(target_storage_root).save!
      cm.reload

      expect(cm.moab_storage_root).to eq(target_storage_root)
      expect(cm.from_moab_storage_root).to eq(orig_storage_root)
      expect(cm.status).to eq('validity_unknown')
      expect(cm.status_details).to be_nil
      expect(cm.last_moab_validation).to be_nil
      expect(cm.last_checksum_validation).to be_nil
      expect(cm.last_version_audit).to be_nil
    end

    it 'queues a checksum validation job' do
      allow(ChecksumValidationJob).to receive(:perform_later).with(cm)
      cm.migrate_moab(target_storage_root).save!
      expect(ChecksumValidationJob).to have_received(:perform_later).with(cm)
    end
  end

  context 'ordered (by last version_audited) and unordered least_recent_version_audit' do
    let!(:newer_timestamp_cm) do
      create(:complete_moab, args.merge(version: 6, last_version_audit: (now - 1.day)))
    end
    let!(:older_timestamp_cm) do
      create(:complete_moab, args.merge(version: 7, last_version_audit: (now - 2.days)))
    end
    let!(:future_timestamp_cm) do
      create(:complete_moab, args.merge(version: 8, last_version_audit: (now + 1.day)))
    end

    describe '.least_recent_version_audit' do
      it 'returns PreservedCopies with nils and PreservedCopies < given date (not orded by last_version_audit)' do
        expect(described_class.least_recent_version_audit(now).sort).to eq [cm, newer_timestamp_cm, older_timestamp_cm]
      end

      it 'returns no PreservedCopies with future timestamps' do
        expect(described_class.least_recent_version_audit(now)).not_to include future_timestamp_cm
      end
    end

    describe '.order_last_version_audit' do
      let(:least_recent_version) { described_class.least_recent_version_audit(now) }

      it 'returns PreservedCopies with nils first, then old to new timestamps' do
        expect(described_class.order_last_version_audit(least_recent_version))
          .to eq [cm, older_timestamp_cm, newer_timestamp_cm]
      end

      it 'returns no PreservedCopies with future timestamps' do
        expect(described_class.order_last_version_audit(least_recent_version))
          .not_to include future_timestamp_cm
      end
    end
  end

  describe 'preserved_object_id and moab_storage_root_id combination' do
    context 'at the model level' do
      it 'must be unique ' do
        expect {
          create(:complete_moab, preserved_object_id: preserved_object.id,
                                 moab_storage_root_id: cm.moab_storage_root_id)
        }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context 'at the db level' do
      it 'must be unique' do
        dup_complete_moab = described_class.new(preserved_object_id: preserved_object.id,
                                                moab_storage_root_id: cm.moab_storage_root_id,
                                                status: status,
                                                version: cm_version)
        expect { dup_complete_moab.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end
  end

  describe '.normalize_date(timestamp)' do
    it 'given a String timestamp, returns a Time object' do
      expect(described_class.send(:normalize_date, '2018-01-22T18:54:48')).to be_a(Time)
    end

    it 'given a Time Object, returns equivalent Time object' do
      expect(described_class.send(:normalize_date, now)).to eq(now)
    end

    it 'given nil, raises TypeError' do
      expect { described_class.send(:normalize_date, nil) }.to raise_error(TypeError, /no implicit conversion/)
    end

    it 'given an unparseable date, raises ArgumentError' do
      expect { described_class.send(:normalize_date, 'an 6') }.to raise_error(ArgumentError, /no time information/)
    end

    it 'given day only returns a Time object' do
      expect(described_class.send(:normalize_date, '2018-02-02')).to be_a(Time)
    end

    it 'given a month only returns Time object' do
      expect(described_class.send(:normalize_date, 'April')).to be_a(Time)
    end

    it 'given a year only, raises ArgumentError' do
      expect { described_class.send(:normalize_date, '2014') }.to raise_error(ArgumentError, /argument out of range/)
    end
  end

  context 'ordered (by fixity_check_expired) and unordered fixity_check_expired methods' do
    let(:fixity_ttl) { preserved_object.preservation_policy.fixity_ttl }
    let!(:old_check_cm1) do
      create(:complete_moab, args.merge(version: 6, last_checksum_validation: now - (fixity_ttl * 2)))
    end
    let!(:old_check_cm2) do
      create(:complete_moab, args.merge(version: 7, last_checksum_validation: now - fixity_ttl - 1.second))
    end
    let!(:recently_checked_cm1) do
      create(:complete_moab, args.merge(version: 8, last_checksum_validation: now - fixity_ttl + 1.second))
    end
    let!(:recently_checked_cm2) do
      create(:complete_moab, args.merge(version: 9, last_checksum_validation: now - (fixity_ttl * 0.1)))
    end

    describe '.fixity_check_expired' do
      it 'returns PreservedCopies that need fixity check' do
        expect(described_class.fixity_check_expired.to_a.sort).to eq [cm, old_check_cm1, old_check_cm2]
      end

      it 'returns no PreservedCopies with timestamps indicating still-valid fixity check' do
        expect(described_class.fixity_check_expired).not_to include(recently_checked_cm1, recently_checked_cm2)
      end
    end

    describe '.order_fixity_check_expired' do
      let(:fixity_check_expired) { described_class.fixity_check_expired }

      it 'returns PreservedCopies that need fixity check, never checked first, then least-recently to most-recently' do
        expect(described_class.order_fixity_check_expired(fixity_check_expired).to_a)
          .to eq [cm, old_check_cm1, old_check_cm2]
      end

      it 'returns no PreservedCopies with timestamps indicating still-valid fixity check' do
        expect(described_class.order_fixity_check_expired(fixity_check_expired))
          .not_to include(recently_checked_cm1, recently_checked_cm2)
      end
    end
  end

  context 'with a persisted object' do
    describe '.by_druid' do
      it 'returns the expected complete moabs' do
        expect(described_class.by_druid(druid).length).to eq 1
        expect(described_class.by_druid('bj102hs9687')).to be_empty
      end
    end

    describe '.by_storage_root' do
      it 'returns the expected complete moab when chained with by_druid' do
        expect(described_class.by_druid(druid).by_storage_root(cm.moab_storage_root).length).to eq 1
        expect(described_class.by_druid(druid).by_storage_root(MoabStorageRoot.first)).to be_empty
      end
    end
  end

  describe '.after_update callback' do
    it 'does not call create_zipped_moab_versions when version is unchanged' do
      cm.size = 234
      expect(cm).not_to receive(:create_zipped_moab_versions!)
      cm.save!
    end

    it 'calls create_zipped_moab_versions when version was changed' do
      cm.version = 55
      expect(cm).to receive(:create_zipped_moab_versions!)
      cm.save!
    end
  end

  describe '.after_save callback' do
    before { allow(ChecksumValidationJob).to receive(:perform_later).and_call_original } # undo rails_helper block

    it 'does not call validate_checksums when status is unchanged' do
      cm.size = 234
      expect(cm).not_to receive(:validate_checksums!)
      cm.save!
    end

    it 'does calls validate_checksums when status is validity_unknown' do
      cm.ok! # object starts out with validity_unknown status
      expect(cm).to receive(:validate_checksums!)
      cm.validity_unknown!
    end
  end

  describe 'Multiple moabs for a druid' do
    let(:druid) { 'ab123cd4567' }
    let(:preserved_object) { create(:preserved_object, druid: druid) }
    let(:cm1) { create(:complete_moab, preserved_object: preserved_object) }
    let(:cm2) { create(:complete_moab, preserved_object: preserved_object) }

    it 'confirms multiple complete moabs have the same druid' do
      expect(cm1).not_to equal(cm2)
      expect(cm1.preserved_object.druid).to equal(cm2.preserved_object.druid)
    end
  end
end
