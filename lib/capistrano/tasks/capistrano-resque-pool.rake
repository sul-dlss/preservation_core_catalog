namespace :resque do
  namespace :pool do
    def rails_env
      fetch(:resque_rails_env) || fetch(:rails_env) || fetch(:stage)
    end

    desc 'Start all the workers and queues'
    task :start do
      on roles(workers) do
        within app_path do
          execute "cd preservation_catalog/current ; bundle exec resque-pool --daemon --environment #{rails_env}"
          execute "cd preservation_catalog/current ; AWS_PROFILE=us_west_2 AWS_BUCKET_NAME=#{fetch(:west_bucket_name)} bundle exec resque-pool -d -E #{rails_env} -c #{west_config_path} -p #{west_pid_path}"
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
      end
    end

    def app_path
      File.join(fetch(:deploy_to), 'current')
    end

    def config_path
      File.join(app_path, '/config/resque-pool.yml')
    end

    def west_config_path
      File.join(app_path, '/config/resque-pool-west.yml')
    end

    def pid_path
      File.join(app_path, '/tmp/pids/resque-pool.pid')
    end

    def west_pid_path
      File.join(app_path, '/tmp/pids/resque-pool-west.pid')
    end

    def pid_file_exists?
      test("[ -f #{pid_path} ]")
    end

    def west_pid_file_exists?
      test("[ -f #{west_pid_path} ]")
    end

    def workers
      fetch(:resque_server_roles) || :app
    end
  end
end
