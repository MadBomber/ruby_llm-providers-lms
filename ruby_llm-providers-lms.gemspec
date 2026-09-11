# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'ruby_llm-providers-lms'
  spec.version = '0.1.0'
  spec.authors = ['madbomber']
  spec.email = ['dvanhoozer@gmail.com']

  spec.summary = 'RubyLLM provider for LM Studio.'
  spec.description = "Adds LM Studio provider support to RubyLLM via LM Studio's " \
                     'OpenAI-compatible local server, with model listings enriched ' \
                     "from LM Studio's native REST API."
  spec.homepage = 'https://github.com/madbomber/ruby_llm-providers-lms'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/releases"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.glob('{lib,spec}/**/*') +
               Dir.glob('.github/workflows/*.yml') +
               Dir.glob('models.json') +
               %w[.flayignore .overcommit.yml .rspec .rubocop.yml Archspec.rb LICENSE README.md]
  spec.require_paths = ['lib']

  spec.add_dependency 'ruby_llm', '>= 2.0.0.rc1'
end
