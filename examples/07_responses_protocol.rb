#!/usr/bin/env ruby
# frozen_string_literal: true

# Protocol switching: LM Studio serves both the Chat Completions API
# (/v1/chat/completions, the default) and the newer Responses API
# (/v1/responses). The LMS provider declares both, so one line flips a
# chat to the Responses dialect.
#
# Streaming and client-side tools work here. `with_schema` does NOT —
# LM Studio ignores the schema on this endpoint and nothing raises, so
# you get prose where you expected JSON. See examples/15 for the same
# question asked of every protocol.
#
#   ruby examples/07_responses_protocol.rb

require_relative 'common'

puts <<~INTRO
  == Responses protocol (#{MODEL}) ==
  Requests now go to /v1/responses instead of /v1/chat/completions.

INTRO

response = new_chat(protocol: :responses).ask('In one sentence, what is the OpenAI Responses API?')

puts response.content
puts
puts "request went to: #{response.raw.env.url}"
