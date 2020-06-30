# frozen_string_literal: true

# Primary Moab service for safely updating the primary moab of a preserved object
class PrimaryMoabService
  def initialize(preserved_object)
    @preserved_object = preserved_object
  end

  def update_primary_moab(new_primary_moab)
    return unless @preserved_object.complete_moabs.include? new_primary_moab
    return unless new_primary_moab.version == @preserved_object.current_version
    return unless new_primary_moab.stats == 'ok'

    @preserved_objects.preserved_objects_primary_moab = new_primary_moab
  end
end
