# frozen_string_literal: true

server 'sul-backup-3.stanford.edu', user: 'pres', roles: %w[app db web resque]

Capistrano::OneTimeKey.generate_one_time_key!
set :rails_env, 'production'
set :bundle_without, 'deploy test'
set :deploy_to, '/opt/app/pres/preservation_catalog'
append :linked_files, "config/newrelic.yml", "config/resque.yml"
set :rvm_custom_path, '/usr/local/rvm'

set :east_bucket_name, 'sul-sdr-aws-us-east-1-test'
set :west_bucket_name, 'sul-sdr-aws-us-west-2-test'
set :south_bucket_name, 'sul-sdr-ibm-us-south-1-test'
