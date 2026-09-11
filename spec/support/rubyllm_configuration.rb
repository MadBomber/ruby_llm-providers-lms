# frozen_string_literal: true

RSpec.shared_context 'with configured RubyLLM' do
  before do
    RubyLLM.configure do |config|
      config.lms_api_key = ENV.fetch('LMS_API_KEY', 'test')
      config.lms_api_base = ENV.fetch('LMS_API_BASE', 'http://localhost:1234/v1')
      config.max_retries = 0
      config.retry_backoff_factor = 0
      config.retry_interval = 0
      config.retry_interval_randomness = 0
    end
  end
end
