# frozen_string_literal: true

namespace :prescat do
  desc 'Migrate storage root, returning druids of all migrated moabs'
  task :processing, [:from, :to] => :environment do |_task, _args|
    migration_service = StorageRootMigrationService.new(args(:from), args(:to))
    migration_service.migrate.each { |druid| puts druid }
  end
end
