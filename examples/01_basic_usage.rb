#!/usr/bin/env ruby
# frozen_string_literal: true

# Basic usage: a one-shot question, a multi-turn conversation, and
# the token accounting that comes back with every response.
#
#   ruby examples/01_basic_usage.rb

require_relative 'common'

puts <<~INTRO
  == Basic usage ==
  Model:  #{MODEL}
  Server: #{RubyLLM.config.lms_api_base}

INTRO

chat = new_chat

# One-shot question.
response = chat.ask('In one sentence, what is LM Studio?')
puts response.content

# The chat object remembers context, so follow-ups just work.
response = chat.ask('Now say that again as a haiku.')

puts <<~FOLLOW_UP

  -- follow-up --
  #{response.content}

  tokens in/out: #{response.tokens.input}/#{response.tokens.output}
FOLLOW_UP
