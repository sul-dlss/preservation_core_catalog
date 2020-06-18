# frozen_string_literal: true

server 'preservation-catalog-tester.stanford.edu', user: 'pres', roles: %w[app db web resque queue_populator]

Capistrano::OneTimeKey.generate_one_time_key!
set :rails_env, 'production'
set :bundle_without, 'deploy test'
set :deploy_to, '/opt/app/pres/preservation_catalog'
set :whenever_roles, [:queue_populator]
