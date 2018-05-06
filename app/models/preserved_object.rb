##
# PreservedObject represents a master record tying together all
# concrete copies of an object that is being preserved.  It does not
# represent a specific stored instance on a specific node, but aggregates
# those instances.
class PreservedObject < ApplicationRecord
  belongs_to :preservation_policy
  has_many :preserved_copies, dependent: :restrict_with_exception
  validates :druid, presence: true, uniqueness: true, format: { with: DruidTools::Druid.pattern }
  validates :current_version, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :preservation_policy, null: false

  def create_archive_copies(version)
    # TODO: is it worth checking that the given version is btwn 0 and #current_version ?
    # TODO: wrap in transaction
    Endpoint.target_endpoints(druid).archive.each do |ep|
      PreservedCopy.find_or_create_by!(preserved_object: self, version: version, endpoint: ep) do |pc|
        pc.status = PreservedCopy::UNREPLICATED_STATUS
        # TODO: does size get set later, after zip is created?
      end
    end
  end
end
