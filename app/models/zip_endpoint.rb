# frozen_string_literal: true

# Metadata about a zip endpoint which stores zipped archives of version directories from Moab
# objects.
class ZipEndpoint < ApplicationRecord
  has_many :zipped_moab_versions, dependent: :restrict_with_exception
  has_and_belongs_to_many :preservation_policies

  # @note Hash values cannot be modified without migrating any associated persisted data.
  # @see [enum docs] http://api.rubyonrails.org/classes/ActiveRecord/Enum.html
  # TODO: switch this to use plain strings representing the class name
  enum delivery_class: {
    S3WestDeliveryJob => 1,
    S3EastDeliveryJob => 2,
    IbmSouthDeliveryJob => 3
  }

  validates :endpoint_name, presence: true, uniqueness: true
  # TODO: after switching to string, validate that input resolves to class which #is_a class of the right type?
  validates :delivery_class, presence: true

  # for the given druid, which zip endpoints should have archive copies, as per the preservation_policy?
  scope :targets, lambda { |druid|
    joins(preservation_policies: [:preserved_objects]).where(preserved_objects: { druid: druid })
  }

  # for a given druid, which zip endpoints have an archive copy of the given version?
  scope :which_have_archive_copy, lambda { |druid, version|
    joins(zipped_moab_versions: [:preserved_object])
      .where(
        preserved_objects: { druid: druid },
        zipped_moab_versions: { version: version }
      )
  }

  # for a given version of a druid, which zip endpoints need an archive copy, based on the governing pres policy?
  scope :which_need_archive_copy, lambda { |druid, version|
    targets(druid).where.not(id: which_have_archive_copy(druid, version))
  }

  # iterates over the zip endpoints enumerated in settings, creating a ZipEndpoint for each if one doesn't
  # already exist.
  # @param preservation_policies [Enumerable<PreservationPolicy>] the list of preservation policies
  #   which the newly created zip endpoints implement.
  # @return [Array<ZipEndpoint>] the ZipEndpoint list for the zip endpoints defined in the config (all
  #   entries, including any entries that may have been seeded already)
  # @note this adds new entries from the config, and leaves existing entries alone, but won't delete anything.
  # TODO: figure out deletion/update based on config?
  def self.seed_from_config(preservation_policies)
    return unless Settings.zip_endpoints
    Settings.zip_endpoints.map do |endpoint_name, endpoint_config|
      find_or_create_by!(endpoint_name: endpoint_name.to_s) do |zip_endpoint|
        zip_endpoint.endpoint_node = endpoint_config.endpoint_node
        zip_endpoint.storage_location = endpoint_config.storage_location
        zip_endpoint.preservation_policies = preservation_policies
        zip_endpoint.delivery_class = delivery_classes[endpoint_config.delivery_class.constantize]
      end
    end
  end

  def audit_class
    raise "No audit class configured for #{endpoint_name}" unless audit_class_setting
    audit_class_setting.constantize
  rescue NameError
    raise "Failed to return audit class based on setting for #{endpoint_name}.  Check setting string for accuracy."
  end

  def to_s
    endpoint_name
  end

  private

  def audit_class_setting
    @audit_class_setting ||= Settings.zip_endpoints[endpoint_name]&.audit_class
  end
end
