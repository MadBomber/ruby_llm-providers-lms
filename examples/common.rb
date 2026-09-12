# frozen_string_literal: true

# Shared setup for the example scripts. Each example starts with:
#
#   require_relative 'common'
#
# which configures RubyLLM to talk to a local LM Studio server
# (`lms server start`, http://localhost:1234/v1 by default).
#
# Override the server location or model with environment variables
# (a .env file in the repo root is honored too):
#
#   LMS_API_BASE=http://otherhost:1234/v1
#   LMS_API_KEY=...              # only if the server sits behind auth
#   LMS_MODEL=qwen/qwen3-4b      # any model id your LM Studio knows

require 'bundler/setup'

begin
  require 'dotenv/load'
rescue LoadError
  # dotenv is only a development dependency; plain ENV works fine.
end

require 'ruby_llm/providers/lms'

MODEL = ENV.fetch('LMS_MODEL', 'qwen/qwen3.8-27b')

RubyLLM.configure do |config|
  config.lms_api_base = ENV.fetch('LMS_API_BASE', 'http://localhost:1234/v1')
  config.lms_api_key = ENV.fetch('LMS_API_KEY', nil) # only if the server requires auth
end

# A fresh chat against the local LM Studio server. Because :lms is a
# local provider, RubyLLM assumes any model id exists — no registry
# lookup, no assume_model_exists needed — and LM Studio just-in-time
# loads the model if it isn't loaded yet.
def new_chat(model: MODEL)
  RubyLLM.chat(model:, provider: :lms)
end
