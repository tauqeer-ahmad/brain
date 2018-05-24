require 'rake'
require 'resque'
require 'resque/server'
require 'resque/scheduler/server'
require 'active_scheduler'
require 'resque/scheduler/tasks'
require 'resque/failure/multiple'
require 'resque/failure/redis'
require 'exception_notification/resque'

rails_root = ENV['RAILS_ROOT'] || File.dirname(__FILE__) + '/../..'
rails_env = ENV['RAILS_ENV'] || 'development'

resque_config = YAML.load_file(rails_root + '/config/resque.yml')

Resque.redis = resque_config[rails_env]
app_name = Rails.application.class.parent_name
Resque.redis.namespace = "resque:#{app_name}"

Resque::Failure::Multiple.classes = [Resque::Failure::Redis, ExceptionNotification::Resque]
Resque::Failure.backend = Resque::Failure::Multiple
