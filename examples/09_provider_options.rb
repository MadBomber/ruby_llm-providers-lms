#!/usr/bin/env ruby
# frozen_string_literal: true

# LM Studio extras: request fields outside OpenAI's vocabulary.
# RubyLLM merges `with_provider_options` into the request payload
# as-is, so the LM Studio-only knobs work today:
#
#   ttl             idle seconds before a JIT-loaded model unloads
#                   (resets on every request; server default 60 min)
#   draft_model     speculative decoding — a small model proposes
#                   tokens the main model verifies; both must share
#                   a tokenizer family
#   top_k           sample only from the k most likely tokens
#   min_p           discard tokens below this base probability
#   repeat_penalty  penalize recently generated tokens
#
# These reach every protocol except :native_chat, whose server rejects
# unknown request keys (see examples/13).
#
#   ruby examples/09_provider_options.rb

require_relative 'common'
require 'json'

EXTRAS = {
  ttl: 300, # unload after 5 idle minutes instead of 60
  top_k: 40,
  min_p: 0.05,
  repeat_penalty: 1.1
  # draft_model: 'qwen/qwen3-0.6b'  # only with a tokenizer-compatible pair
}.freeze

puts <<~INTRO
  == LM Studio provider options (#{MODEL}) ==
  Sending: #{EXTRAS.inspect}

INTRO

response = new_chat
           .with_provider_options(**EXTRAS)
           .ask('Reply with exactly: options received')

puts response.content

sent = JSON.parse(response.raw.env.request_body)
on_the_wire = sent.slice(*EXTRAS.keys.map(&:to_s))

puts <<~PROOF

  -- proof from the wire --
  The request body carried the LM Studio-only fields verbatim:
    #{on_the_wire}
PROOF
