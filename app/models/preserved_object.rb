##
# PreservedObject represents a master record tying together all
# concrete copies of an object that is being preserved.  It does not
# represent a specific stored instance on a specific node, but aggregates
# those instances.
class PreservedObject < ApplicationRecord
  # NOTE: The size field stored in PreservedObject is approximate,as it is determined from size
  # on disk (which can vary from machine to machine). This field value should not be used for
  # fixity checking!
  belongs_to :preservation_policy
  has_many :preservation_copies
  validates :druid, presence: true, uniqueness: true
  validates :current_version, presence: true
  validates :preservation_policy, null: false

  def self.update_or_create(druid, current_version: nil, size: nil, preservation_policy: nil)
    existing_rec = find_by(druid: druid)
    if exists?(druid: druid)
      # TODO: add more info, e.g. caller, timestamp written to db
      Rails.logger.debug "update #{druid} called and object exists"
      if current_version
        version_comparison = existing_rec.current_version <=> current_version
        update_entry_per_compare(version_comparison, existing_rec, druid, current_version, size)
      end
      true
    else
      Rails.logger.warn "update #{druid} called but object not found; writing object" # TODO: add more info
      create(druid: druid, current_version: current_version, size: size, preservation_policy: preservation_policy)
      false
    end
  end

  private_class_method
  def self.update_entry_per_compare(version_comparison, existing_rec, druid, current_version, size)
    if version_comparison.zero?
      Rails.logger.info "#{druid} incoming version is equal to db version"
      existing_rec.touch
    elsif version_comparison == 1
      # TODO: needs manual intervention until automatic recovery services implemented
      Rails.logger.error "#{druid} incoming version smaller than db version"
      existing_rec.touch
    elsif version_comparison == -1
      Rails.logger.info "#{druid} incoming version is greater than db version"
      existing_rec.current_version = current_version
      existing_rec.size = size if size
      existing_rec.save
    end
  end
end
