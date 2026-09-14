#!/usr/bin/env ruby
# frozen_string_literal: true

# Inference stats. LM Studio's native /api/v0/chat/completions is a strict
# superset of the OpenAI-compatible endpoint: same request, same choices
# and usage, but it fills in the `stats` block that /v1/chat/completions
# returns empty, and adds `model_info` and `runtime`. The provider
# registers it as the :native_v0 protocol, so switching is one config line
# and nothing else about the chat changes (streaming and tool calls work
# the same way).
#
# RubyLLM has no field for local-inference telemetry, so it arrives
# through Message#raw. This demo asks the same question twice, once on
# each protocol, to show what the native endpoint adds.
#
# Note on the default protocol's `stats`: it is {} on an ordinary request.
# It carries draft-token counters only when the model was loaded with a
# `draft_model` for speculative decoding — never the timing figures.
#
#   ruby examples/11_native_stats.rb

require_relative 'common'

QUESTION = 'In one sentence, what is a GGUF file?'

# A context keeps the override off the global configuration, so the
# default protocol is still there to compare against.
native_chat = RubyLLM.context { |config| config.lms_protocol = :native_v0 }
                     .chat(model: MODEL, provider: :lms)

default_response = new_chat.ask(QUESTION)
native_response = native_chat.ask(QUESTION)
stats = native_response.raw.body['stats']

if stats.nil? || stats['tokens_per_second'].nil?
  puts <<~UNSUPPORTED
    == Inference stats (#{MODEL}) ==

    This LM Studio build answered /api/v0/chat/completions without timing
    stats (got #{stats.inspect}). Upgrade LM Studio to see per-request
    telemetry.
  UNSUPPORTED
  exit
end

model_info = native_response.raw.body['model_info'] || {}
runtime = native_response.raw.body['runtime'] || {}

puts <<~REPORT
  == Inference stats via the :native_v0 protocol (#{MODEL}) ==

  -- default protocol (:chat_completions) --
  endpoint:  #{default_response.raw.env.url}
  stats:     #{default_response.raw.body['stats'].inspect}
             (empty, or speculative-decoding counters — never timings)

  -- native protocol (:native_v0) --
  endpoint:  #{native_response.raw.env.url}

  tokens per second:    #{stats['tokens_per_second'].round(2)}
  time to first token:  #{stats['time_to_first_token'].round(4)}s
  generation time:      #{stats['generation_time'].round(4)}s
  stop reason:          #{stats['stop_reason']}

  model_info:  arch=#{model_info['arch']} quant=#{model_info['quant']} context=#{model_info['context_length']}
  runtime:     #{runtime['name']} #{runtime['version']}

  Both protocols returned the same kind of answer:
  #{native_response.content}
REPORT
