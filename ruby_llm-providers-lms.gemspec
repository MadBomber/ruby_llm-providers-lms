# frozen_string_literal: true

# Read the literal rather than loading the provider: the gemspec is evaluated
# before this gem's lib/ is on the load path, so requiring it would resolve
# against an installed copy of the gem instead.
gem_version = File.read(File.expand_path('lib/ruby_llm/providers/lms/version.rb', __dir__))[/VERSION = '([^']+)'/, 1]

Gem::Specification.new do |spec|
  spec.name = 'ruby_llm-providers-lms'
  spec.version = gem_version
  spec.authors = ['madbomber']
  spec.email = ['dvanhoozer@gmail.com']

  spec.summary = 'RubyLLM provider for LM Studio.'
  spec.description = "Adds LM Studio provider support to RubyLLM via LM Studio's " \
                     'OpenAI-compatible local server, with model listings enriched ' \
                     "from LM Studio's native REST API."
  spec.homepage = 'https://github.com/madbomber/ruby_llm-providers-lms'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Ship what the gem needs at runtime. The suite and its VCR cassettes --
  # recorded conversations with the author's own models -- stay in the repo.
  spec.files = Dir.glob('lib/**/*.rb') +
               Dir.glob('models.json') +
               %w[CHANGELOG.md LICENSE README.md]
  spec.require_paths = ['lib']

  spec.add_dependency 'ruby_llm', '>= 2.0.0.rc1'
end
