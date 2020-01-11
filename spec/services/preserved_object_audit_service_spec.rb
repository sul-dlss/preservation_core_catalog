# frozen_string_literal: true

RSpec.describe PreservedObjectAuditService do
  context 'no preserved object' do
    context 'no moabs on disk' do
      it 'raises an error' do
      end
    end

    context 'moabs on disk exist' do
      it 'creates the preserved object' do
      end
      it 'proceeds with audit' do
      end
    end
  end

  context 'missing complete_moab' do
    it 'creates the complete_moab' do
    end
    it 'adds to results' do
    end
    it 'proceeds with audit' do
    end
  end

  context 'missing moab on disk' do
    it 'updates status' do
    end
    it 'adds to results' do
    end
  end

  context 'complete_moab and moab on disk versions match' do
    context 'complete_moab status is ok' do
      it 'updates timestamps' do
      end
      it 'adds to results' do
      end
    end
    context 'complete_moab status is not ok' do
      it 'updates timestamps' do
      end
      it 'validates' do
      end
    end
  end

  context 'invalid moab' do
    it 'updates timestamps' do
    end
    it 'updates status' do
    end
    it 'adds to results' do
    end
  end

  context 'valid moab' do
    it 'updates timestamps' do
    end
  end

  context 'moab version < complete_moab version' do
    it 'updates status' do
    end
    it 'adds to results' do
    end
  end

  context 'moab version > complete_moab version' do
    context 'preserved object version is correct' do
      it 'updates version' do
      end
      it 'updates size' do
      end
      it 'adds to results' do
      end
      it 'does not update preserved object version' do
      end
    end

    context 'preserved object version is incorrect' do
      it 'updates version' do
      end
      it 'updates size' do
      end
      it 'adds to results' do
      end
      it 'updates preserved object version' do
      end
    end
  end

  context 'preserved object version and complete_moab version do not match' do
    it 'adds to results' do
    end
  end

  context 'complete_moab with MOAB_NOT_FOUND status' do
    context 'other complete_moabs with a different status' do
      it 'deletes complete_moab with MOAB_NOT_FOUND status' do
      end
      it 'adds to results' do
      end
    end
    context 'no other complete_moabs with a different status' do
      it 'does not delete complete_moab with MOAB_NOT_FOUND status' do
      end
    end
  end
end