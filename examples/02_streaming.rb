#!/usr/bin/env ruby
# frozen_string_literal: true

# Streaming: pass a block to `ask` and chunks arrive as the model
# generates them — no waiting for the full completion. With a local
# LM Studio server the first token typically lands fast because
# nothing leaves your machine.
#
#   ruby examples/02_streaming.rb

require_relative 'common'

puts <<~INTRO
  == Streaming (#{MODEL}) ==

INTRO

chat = new_chat

response = chat.ask('Tell a three-sentence story about a robot learning Ruby.') do |chunk|
  print chunk.content
  $stdout.flush
end

puts <<~SUMMARY


  -- after the stream --
  The block saw the text incrementally; `ask` still returns the
  assembled response: #{response.content.length} characters,
  #{response.tokens.output} output tokens.
SUMMARY
