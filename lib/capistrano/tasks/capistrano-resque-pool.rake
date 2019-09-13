# frozen_string_literal: true

namespace :resque do
  namespace :pool do
    def rails_env
      fetch(:resque_rails_env) || fetch(:rails_env) || fetch(:stage)
    end

    desc 'Hot swap workers and queues'
    task :hot_swap do
      on roles(workers) do
        within app_path do
          execute "cd preservation_catalog/current ; bundle exec resque-pool --hot-swap --lock #{lock_path} --daemon --environment #{rails_env}"
          execute "cd preservation_catalog/current ; AWS_PROFILE=us_west_2 AWS_BUCKET_NAME=#{fetch(:west_bucket_name)} bundle exec resque-pool -H -l #{west_lock_path} -d -E #{rails_env} -c #{west_config_path} -p #{west_pid_path}"
          execute "cd preservation_catalog/current ; AWS_PROFILE=us_south AWS_BUCKET_NAME=#{fetch(:south_bucket_name)} bundle exec resque-pool -H -l #{south_lock_path} -d -E #{rails_env} -c #{south_config_path} -p #{south_pid_path}"
        end
      end
    end

    desc 'Start all the workers and queues'
    task :start do
      on roles(workers) do
        within app_path do
          execute "cd preservation_catalog/current ; bundle exec resque-pool --daemon --environment #{rails_env}"
          execute "cd preservation_catalog/current ; AWS_PROFILE=us_west_2 AWS_BUCKET_NAME=#{fetch(:west_bucket_name)} bundle exec resque-pool -d -E #{rails_env} -c #{west_config_path} -p #{west_pid_path}"
          execute "cd preservation_catalog/current ; AWS_PROFILE=us_south AWS_BUCKET_NAME=#{fetch(:south_bucket_name)} bundle exec resque-pool -d -E #{rails_env} -c #{south_config_path} -p #{south_pid_path}"
        end
      end
    end

    desc 'Gracefully shut down workers and shutdown the manager after all workers are done'
    task :stop do
      on roles(workers) do
        if pid_file_exists?
          pid = capture(:cat, pid_path)
          if test "kill -0 #{pid} > /dev/null 2>&1"
            execute :kill, "-s QUIT #{pid}"
          else
            info "Process #{pid} from #{pid_path} is not running, cleaning up stale PID file"
            execute :rm, pid_path
          end
        end
        if west_pid_file_exists?
          pid = capture(:cat, west_pid_path)
          if test "kill -0 #{pid} > /dev/null 2>&1"
            execute :kill, "-s QUIT #{pid}"
          else
            info "Process #{pid} from #{west_pid_path} is not running, cleaning up stale PID file"
            execute :rm, west_pid_path
          end
        end
        if south_pid_file_exists?
          pid = capture(:cat, south_pid_path)
          if test "kill -0 #{pid} > /dev/null 2>&1"
            execute :kill, "-s QUIT #{pid}"
          else
            info "Process #{pid} from #{south_pid_path} is not running, cleaning up stale PID file"
            execute :rm, south_pid_path
          end
        end
      end
    end

    def app_path
      File.join(fetch(:deploy_to), 'current')
    end

    def lock_path
      File.join(app_path, '/tmp/resque-pool.lock')
    end

    def west_lock_path
      File.join(app_path, '/tmp/resque-pool-west.lock')
    end

    def south_lock_path
      File.join(app_path, '/tmp/resque-pool-south.lock')
    end

    def config_path
      File.join(app_path, '/config/resque-pool.yml')
    end

    def west_config_path
      File.join(app_path, '/config/resque-pool-west.yml')
    end

    def south_config_path
      File.join(app_path, '/config/resque-pool-south.yml')
    end

    def pid_path
      File.join(app_path, '/tmp/pids/resque-pool.pid')
    end

    def west_pid_path
      File.join(app_path, '/tmp/pids/resque-pool-west.pid')
    end

    def south_pid_path
      File.join(app_path, '/tmp/pids/resque-pool-south.pid')
    end

    def pid_file_exists?
      test("[ -f #{pid_path} ]")
    end

    def west_pid_file_exists?
      test("[ -f #{west_pid_path} ]")
    end

    def south_pid_file_exists?
      test("[ -f #{south_pid_path} ]")
    end

    def workers
      fetch(:resque_server_roles) || :app
    end
  end
end
