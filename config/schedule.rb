# Use this file to easily define all of your cron jobs.
# Learn more: http://github.com/javan/whenever

# also overriding b/c whenever adds --silent (https://github.com/javan/whenever/issues/524, #541)
job_type :sat_only_rake, "cd :path && bin/is_it_saturday.sh && :environment_variable=:environment :bundle_command rake :task :output"

# these append to existing logs
every '0 5 1-7 * *', roles: [:m2c] do
  set :output, standard: 'log/m2c.log', error: 'log/m2c-err.log'
  sat_only_rake 'm2c:all_roots'
end
every '0 5 15-21 * *', roles: [:m2c] do
  set :output, standard: 'log/m2c.log', error: 'log/m2c-err.log'
  sat_only_rake 'm2c:all_roots'
end

every '0 5 8-14 * *', roles: [:c2m] do
  set :output, standard: 'log/c2m.log', error: 'log/c2m-err.log'
  sat_only_rake "c2m:all_roots[`date --iso-8601=s`]"
end
every '0 5 22-28 * *', roles: [:c2m] do
  set :output, standard: 'log/c2m.log', error: 'log/c2m-err.log'
  sat_only_rake "c2m:all_roots[`date --iso-8601=s`]"
end
every :sunday, at: '1am', roles: [:cv] do
  set :output, standard: 'log/cv.log', error: 'log/cv-err.log'
  rake "cv:all_roots"
end
