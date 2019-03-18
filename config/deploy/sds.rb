server 'preservation-catalog-sds-01.stanford.edu', user: 'pres', roles: %w[app db web]
server 'preservation-catalog-sds-02.stanford.edu', user: 'pres', roles: %w[app resque queue_populator]
server 'preservation-catalog-sds-03.stanford.edu', user: 'pres', roles: %w[app resque]
server 'preservation-catalog-sds-04.stanford.edu', user: 'pres', roles: %w[app resque cache_cleaner]

Capistrano::OneTimeKey.generate_one_time_key!
set :rails_env, 'production'
set :bundle_without, 'deploy test'
set :deploy_to, '/opt/app/pres/preservation_catalog'
set :whenever_roles, [:queue_populator, :cache_cleaner]
