# frozen_string_literal: true

VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  config.hook_into :webmock
  config.default_cassette_options = { record: ENV['CI'] ? :none : :once }
  config.allow_http_connections_when_no_cassette = true
  config.filter_sensitive_data('<LMS_API_KEY>') { ENV.fetch('LMS_API_KEY', nil) }

  # Normalize the recorder's server address to the default so cassettes
  # replay on any machine (CI included) without LMS_API_BASE set. The
  # placeholder must be a parseable URI, not a <TOKEN>: VCR parses every
  # cassette URI on replay and raises URI::InvalidURIError otherwise.
  config.filter_sensitive_data(RubyLLM::Providers::LMS::DEFAULT_API_BASE) do
    base = ENV.fetch('LMS_API_BASE', nil)
    base unless base.nil? || base == RubyLLM::Providers::LMS::DEFAULT_API_BASE
  end

  config.before_record do |interaction|
    next unless interaction.request.headers['Authorization']

    interaction.request.headers['Authorization'] = ['Bearer <AUTH_TOKEN>']
  end
end
