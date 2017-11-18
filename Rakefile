# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative 'config/application'

Rails.application.load_tasks

require 'rubocop/rake_task'
RuboCop::RakeTask.new

task default: [:spec, :rubocop]

task :travis_setup_postgres do
  sh("psql -U postgres -f db/scripts/pres_test_setup.sql")
end

require 'audit/moab_to_catalog.rb'
desc 'populate the catalog with the contents of the online storage roots'
task :seed_catalog, [:profile] => [:environment] do |_t, args|
  unless args[:profile] == 'profile' || args[:profile].nil?
    p "Usage: rake seed_catalog || rake seed_catalog[profile]"
    exit
  end
  m2c = MoabToCatalog.new
  puts "#{Time.now.utc.iso8601} Seeding the database from all storage roots..."
  if args[:profile] == 'profile'
    puts 'When done, check log/seed_from_disk[TIMESTAMP].log for profiling details'
    m2c.seed_from_disk_with_profiling
  elsif args[:profile].nil?
    m2c.seed_from_disk
  end
  puts "#{Time.now.utc.iso8601} Done"
end
