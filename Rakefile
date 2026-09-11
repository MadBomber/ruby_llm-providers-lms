# frozen_string_literal: true

require 'bundler/setup'
require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

desc 'Refresh the LMS model catalog'
task :models do
  require 'dotenv/load'
  require_relative 'lib/ruby_llm/providers/lms'

  RubyLLM.configure do |config|
    config.lms_api_key = ENV.fetch('LMS_API_KEY', nil)
    config.lms_api_base = ENV.fetch('LMS_API_BASE', 'http://localhost:1234/v1')
  end

  provider = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config)
  models = provider.list_models
  abort 'LMS returned no models' if models.empty?

  RubyLLM::Models.new(models).save_to_json(File.expand_path('models.json', __dir__))
end

desc 'Run Flay duplicate detection'
task :flay do
  sh 'bundle exec flay --mass 70 lib spec'
end

desc 'Run ArchSpec architecture checks'
task :archspec do
  sh 'bundle exec archspec check'
end

task default: %i[rubocop flay archspec spec]
