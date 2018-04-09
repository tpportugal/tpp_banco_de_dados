source 'https://rubygems.org'

gem 'rails', '4.2.10'

# TPP Datastore components
path 'components' do
  gem 'datastore_admin'
end

# process runner
gem 'foreman', group: :development

# configuration
gem 'figaro'

# data stores
gem 'pg', '~> 0.18'
gem 'activerecord-postgis-adapter'
gem 'activerecord-import'
gem 'redis-rails'
# NOTE: pegging version of Redis gems
# because of past operations issues: https://github.com/transitland/transitland-datastore/pull/880
# hopefully will be fixed in future versions
gem 'redis'
gem 'redis-actionpack'
gem 'redis-rack'

# background processing
gem 'sidekiq', '< 6'
gem 'sidekiq-unique-jobs', group: [:development, :staging, :production] # doesn't play well with test
gem 'sidekiq-limit_fetch'
gem "sidekiq-cron", "~> 0.6.3"

# data model
gem 'squeel'
gem 'enumerize'
gem 'gtfs', github: 'Rui-Santos/tpp-gtfs', tag: 'd494696cdd5af0adea339fc01c48e63bd840af59'
gem 'rgeo-geojson'
gem 'c_geohash', require: 'geohash'
gem 'json'
gem 'json-schema'
gem 'email_validator'
gem 'tzinfo'

# data export
gem 'google-protobuf'

# text matching
gem 'text'

# authentication and authorization
gem 'rack-cors', require: 'rack/cors'
gem 'devise'
gem 'jwt'

# providing API
gem 'active_model_serializers', '~> 0.10'
gem 'oj'

# consuming other APIs
gem 'faraday'

# file attachments
gem 'carrierwave', '~>1.1.0'

# development tools
gem 'better_errors', group: :development
gem 'binding_of_caller', group: :development
gem 'byebug', group: [:development, :test]
gem 'pry-byebug', group: [:development, :test]
gem 'pry-rails', group: [:development, :test]
gem 'pry-rescue', group: [:development, :test]
gem 'pry-stack_explorer', group: [:development, :test]
gem 'active_record_doctor', group: :development

# code coverage and documentation
gem 'rails-erd', group: :development
gem 'annotate', group: :development
gem 'simplecov', require: false, group: [:development, :test]

# testing
gem 'database_cleaner', group: :test
gem 'factory_girl_rails', require: false, group: [:development, :test]
gem 'ffaker', group: [:development, :test]
gem 'rspec-rails', group: [:development, :test]
gem 'rspec-sidekiq', group: :test
gem 'vcr', group: :test
gem 'webmock', group: :test
gem 'airborne', group: :test
gem 'timecop', group: :test
gem 'rspec_junit_formatter', '0.2.2', group: :test
# ^ for CircleCI: https://circleci.com/docs/test-metadata#rspec

# exception monitoring
gem 'sentry-raven', group: [:staging, :production]

# logging
gem 'logstasher'
gem 'sidekiq-logging-json'
gem 'ruby-progressbar'

# database query performance monitoring/analysis
gem 'bullet', group: :development
gem 'pghero', group: [:development, :staging, :production] # mounted at /admin/postgres
gem 'marginalia', group: [:development, :staging]

# web server
gem 'unicorn', group: [:staging, :production]
gem 'puma'

# profiling
gem 'memory_profiler', group: [:test, :development]

#mailer
gem 'mailcatcher'
