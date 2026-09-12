#!/usr/bin/env ruby
# frozen_string_literal: true

# Protocol switching: LM Studio serves both the Chat Completions API
# (/v1/chat/completions, the default) and the newer Responses API
# (/v1/responses). The LMS provider declares both, so one config line
# flips every chat to the Responses dialect.
#
#   ruby examples/07_responses_protocol.rb

require_relative 'common'

RubyLLM.configure { |config| config.lms_protocol = :responses }

puts <<~INTRO
  == Responses protocol (#{MODEL}) ==
  Requests now go to /v1/responses instead of /v1/chat/completions.

INTRO

response = new_chat.ask('In one sentence, what is the OpenAI Responses API?')

puts response.content
puts
puts "request went to: #{response.raw.env.url}"
