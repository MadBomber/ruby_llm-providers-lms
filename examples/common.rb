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
#   LMS_DECISION_MODEL=kev-0.8b  # a decision model, for the judgment demos

require 'bundler/setup'

begin
  require 'dotenv/load'
rescue LoadError
  # dotenv is only a development dependency; plain ENV works fine.
end

require 'ruby_llm/providers/lms'

MODEL = ENV.fetch('LMS_MODEL', 'qwen/qwen3.8-27b')

# The judgment demos (16-20) need a decision model: one LM Studio lists with
# `type: "decision"`, such as the open GGUFs ggml-org/Kev-0.8B-GGUF,
# LiquidAI/d1-omni-600M-GGUF or ggml-org/Clef-Flash-GGUF. D1 Omni 600M is the
# default because it is small and also reads images.
#
#   lms get https://huggingface.co/LiquidAI/d1-omni-600M-GGUF
DECISION_MODEL = ENV.fetch('LMS_DECISION_MODEL', 'd1-omni-600m')

RubyLLM.configure do |config|
  config.lms_api_base = ENV.fetch('LMS_API_BASE', 'http://localhost:1234/v1')
  config.lms_api_key = ENV.fetch('LMS_API_KEY', nil) # only if the server requires auth
end

# A fresh chat against the local LM Studio server. Because :lms is a
# local provider, RubyLLM assumes any model id exists — no registry
# lookup, no assume_model_exists needed — and LM Studio just-in-time
# loads the model if it isn't loaded yet.
#
# Pass +protocol:+ to speak one of the other dialects LM Studio serves
# (:responses, :anthropic, :native_v0, :native_chat). It is scoped to the
# returned chat through a RubyLLM context, so the global configuration —
# and every other demo — keeps the default protocol.
def new_chat(model: MODEL, protocol: nil)
  return RubyLLM.chat(model:, provider: :lms) if protocol.nil?

  RubyLLM.context { |config| config.lms_protocol = protocol }
         .chat(model:, provider: :lms)
end

# A RubyLLM context whose judgments go to one of LM Studio's two decision
# endpoints: :decisions (POST /v1/decisions, the default) or :system_one
# (POST /v1/systemone). Pass it as `context:` to RubyLLM.judge or Judge.judge.
def judgment_context(endpoint)
  RubyLLM.context { |config| config.lms_judgment_protocol = endpoint }
end
