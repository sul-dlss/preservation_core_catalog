# metadata about a zipped version directory from a Moab
class ArchivePreservedCopy < ApplicationRecord
  belongs_to :preserved_copy
  belongs_to :archive_endpoint

  # @note Hash values cannot be modified without migrating any associated persisted data.
  # @see [enum docs] http://api.rubyonrails.org/classes/ActiveRecord/Enum.html
  enum status: {
    'ok' => 0,
    'unreplicated' => 1,
    'archive_not_found' => 2,
    'invalid_checksum' => 3
  }

  validates :archive_endpoint, presence: true
  validates :preserved_copy, presence: true
  validates :status, inclusion: { in: statuses.keys }
  validates :version, presence: true
end