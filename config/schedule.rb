# frozen_string_literal: true

# Use this file to easily define all of your cron jobs.
# Learn more: http://github.com/javan/whenever

# these append to existing logs
every :tuesday, roles: [:queue_populator] do
  set :output, standard: nil, error: 'log/m2c-err.log'
  runner 'MoabStorageRoot.find_each(&:m2c_check!)'
end

every :wednesday, roles: [:queue_populator] do
  set :output, standard: nil, error: 'log/c2a-err.log'
  runner 'PreservedObject.archive_check_expired.find_each(&:audit_moab_version_replication!)'
end

# every :friday, roles: [:queue_populator] do
#   set :output, standard: nil, error: 'log/c2m-err.log'
#   runner 'MoabStorageRoot.find_each(&:c2m_check!)'
# end

# every :sunday, at: '1am', roles: [:queue_populator] do
#   set :output, standard: nil, error: 'log/cv-err.log'
#   runner 'MoabStorageRoot.find_each(&:validate_expired_checksums!)'
# end

# every :hour, roles: [:cache_cleaner] do
#   set :output, standard: '/var/log/preservation_catalog/zip_cache_cleanup.log'
#   rake 'prescat:cache_cleaner:stale_files'
# end

# every :day, at: '1:15am', roles: [:cache_cleaner] do
#   set :output, standard: '/var/log/preservation_catalog/zip_cache_cleanup.log'
#   rake 'prescat:cache_cleaner:empty_directories'
# end
