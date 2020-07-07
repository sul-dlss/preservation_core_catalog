# frozen_string_literal: true

require 'csv'

namespace :prescat do
  namespace :cache_cleaner do
    desc 'Clean zip storage cache of empty directories'
    task empty_directories: :environment do
      `find #{Settings.zip_storage} -not -path "*/\.*" -type d -empty -delete`
    end

    desc 'Clean zip storage cache of stale checksum & zip files'
    task stale_files: :environment do
      `find #{Settings.zip_storage} -mindepth 3 -type f -amin #{Settings.zip_cache_expiry_time} -delete`
    end
  end

  desc 'Migrate storage root, returning druids of all migrated moabs'
  task :migrate_storage_root, [:from, :to] => :environment do |_task, args|
    puts 'This will move all complete_moabs from the old storage root to a new storage root.'
    puts 'WARNING: expects that "from" storage root is no longer being written to (no Moabs being created or modified)!'
    print 'Enter YES to continue: '
    input = $stdin.gets.chomp
    next unless input == 'YES'

    migration_service = StorageRootMigrationService.new(args[:from], args[:to])
    timestamp_str = DateTime.now.utc.iso8601.gsub(':', '') # colons are a pain to deal with on CLI, so just remove them
    filename = File.join(Rails.root, 'log', "migrate_moabs_from_#{args[:from]}_to_#{args[:to]}_#{timestamp_str}.csv")
    count = 0
    CSV.open(filename, 'w') do |csv|
      csv << ['druid']
      migration_service.migrate.each do |druid|
        csv << [druid]
        count += 1
      end
    end
    puts "migrated #{count} CompleteMoab records from #{args[:from]} to #{args[:to]}, druid list available at #{filename}"
  end

  namespace :reports do
    desc 'query for druids on storage root & dump to CSV (2nd & 3rd arg optional)'
    task :msr_druids, [:storage_root_name, :report_tag, :csv_filename] => [:environment] do |_task, args|
      reporter = MoabStorageRootReporter.new(storage_root_name: args[:storage_root_name])
      csv_loc = reporter.write_to_csv(reporter.druid_csv_list, report_type: 'druids', report_tag: args[:report_tag], filename: args[:csv_filename])
      puts "druids for #{args[:storage_root_name]} written to #{csv_loc}"
    end

    desc 'query for druids on storage root & dump details to CSV (2nd & 3rd arg optional)'
    task :msr_moab_status_details, [:storage_root_name, :report_tag, :csv_filename] => [:environment] do |_task, args|
      reporter = MoabStorageRootReporter.new(storage_root_name: args[:storage_root_name])
      data = reporter.moab_detail_csv_list
      csv_loc = reporter.write_to_csv(data, report_type: 'moab_status_details', report_tag: args[:report_tag], filename: args[:csv_filename])
      puts "druid details for #{args[:storage_root_name]} written to #{csv_loc}"
    end

    desc 'query for druids on storage root & dump audit error details to CSV (2nd & 3rd arg optional)'
    task :msr_moab_audit_errors, [:storage_root_name, :report_tag, :csv_filename] => [:environment] do |_task, args|
      reporter = MoabStorageRootReporter.new(storage_root_name: args[:storage_root_name])
      data = reporter.moab_detail_csv_list(errors_only: true)
      csv_loc = reporter.write_to_csv(data, report_type: 'moab_audit_errors', report_tag: args[:report_tag], filename: args[:csv_filename])
      puts "druids with errors details for #{args[:storage_root_name]} written to #{csv_loc}"
    end
  end

  namespace :audit do
    desc 'run M2C (moab to catalog) validation on a storage root'
    task :m2c, [:storage_root_name] => [:environment] do |_task, args|
      msr = MoabStorageRoot.find_by!(name: args[:storage_root_name])
      msr.m2c_check!
    end

    desc 'run C2M (catalog to moab) validation on a storage root'
    task :c2m, [:storage_root_name] => [:environment] do |_task, args|
      msr = MoabStorageRoot.find_by!(name: args[:storage_root_name])
      msr.c2m_check!
    end

    desc 'run CV (checksum validation) for all druids on a storage root'
    task :cv, [:storage_root_name] => [:environment] do |_task, args|
      MoabStorageRoot.find_by!(name: args[:storage_root_name]).complete_moabs.find_each(&:validate_checksums!)
    end
  end

  namespace :druid do
    desc "verify zip parts on cloud storage roots"
    task :parts, [:druid, :version] => [:environment] do |_task, args|
      druid = args[:druid]
      versions(druid)
      version = args[:version]
      cm = CompleteMoab.by_druid(druid).first
      next if cm.nil?

      MoabReplicationAuditJob.perform_now(cm)
      cm.reload
      # ZipPart.joins(zipped_moab_version: [{ complete_moab: [:preserved_object] }, :zip_endpoint]).where(preserved_objects: { druid: druid }).pluck(:druid, 'current_version AS highest_version', 'zipped_moab_versions.version AS zip_version', :endpoint_name, :status, :suffix, :parts_count, :size)
      %w(aws_s3_east_1 aws_s3_west_2).each do |endpoint|
        rel = cloud_rel_for(cm, endpoint)
        cm.zipped_moab_versions.each do |zmv|
          zmv_version = rel.find_by(version: zmv.version)
          # TODO: Make this audit dynamic per provider (aws, ibm)
          audit = PreservationCatalog::S3::Audit.new(zmv_version, AuditResults.new(druid, zmv.version, cm.moab_storage_root, 'manual_cloud_archive_audit'))
          audit.send(:bucket)
          zparts_objects = zmv_version.zip_parts.map { |part| aws_audit.send(:bucket).object(part.s3_key) }
          zparts_objects.each { |zpart| puts "Key = #{zpart.key} Found = #{zpart.exists?}" }
        end
      end

      rel = cloud_rel_for(cm, 'ibm_us_south')
      cm.zipped_moab_versions.each do |zmv|
        zmv_version = rel.find_by(version: zmv.version)
        # TODO: Make this audit dynamic per provider (aws, ibm)
        audit = PreservationCatalog::Ibm::Audit.new(zmv_version, AuditResults.new(druid, zmv.version, cm.moab_storage_root, 'manual_cloud_archive_audit'))
        audit.send(:bucket)
        zparts_objects = zmv_version.zip_parts.map { |part| aws_audit.send(:bucket).object(part.s3_key) }
        zparts_objects.each { |zpart| puts "Key = #{zpart.key} Found = #{zpart.exists?}" }
      end
    end
  end
end

def cloud_rel_for(complete_moab, endpoint) do
  cm.zipped_moab_versions.where(zip_endpoint: ZipEndpoint.where(endpoint_name: endpoint))
end