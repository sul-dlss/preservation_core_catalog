##
# metadata about a specific replication endpoint
class EndpointType < ApplicationRecord
  has_many :endpoints, dependent: :restrict_with_exception

  validates :type_name, presence: true, uniqueness: true
  # TODO: maybe endpoint_class should be an enum or a constant?
  validates :endpoint_class, presence: true

  # iterates over the endpoint types enumerated in the settings, creating any that don't already exist.
  # returns an array with the result of the ActiveRecord find_or_create_by! call for each settings entry (i.e.,
  # the EndpointType rows defined in the config, whether newly created by this call, or previously created).
  # NOTE: this adds new entries from the config, and leaves existing entries alone, but won't delete anything.
  # TODO: figure out deletion based on config?
  def self.seed_from_config
    Settings.endpoint_types.map do |endpoint_type_name, endpoint_type_config|
      # we want to find only by the name, but we want to define the endpoint_class too if we actually add a row
      find_or_create_by!(type_name: endpoint_type_name.to_s) do |endpoint_type|
        endpoint_type.endpoint_class = endpoint_type_config.endpoint_class
      end
    end
  end
end
