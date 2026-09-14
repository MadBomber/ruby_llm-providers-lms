#!/usr/bin/env ruby
# frozen_string_literal: true

# The Anthropic API. LM Studio serves Anthropic's Messages API at
# POST /v1/messages beside the OpenAI and native surfaces, so code written
# against Claude can point at a local model without changing how it talks.
# RubyLLM's stock Anthropic protocol drives it — no credentials, and no
# anthropic-version header.
#
# Streaming and client-side tools work here. Structured output does not:
# LM Studio ignores `with_schema` on this endpoint and nothing raises, so
# you get prose where you expected JSON. This demo shows all three.
#
#   ruby examples/12_anthropic_protocol.rb

require_relative 'common'

# A client-side tool: RubyLLM runs #execute in this process when the
# model asks for it, then feeds the result back as a tool_result block.
class Weather < RubyLLM::Tool
  description 'Gets the current weather for a city'
  parameter :city, description: 'City name'

  def execute(city:)
    "Weather in #{city}: 15°C, wind 10 km/h"
  end
end

SCHEMA = {
  type: 'object',
  properties: { name: { type: 'string' }, age: { type: 'integer' } },
  required: %w[name age]
}.freeze

puts <<~INTRO
  == The Anthropic API (#{MODEL}) ==
  Requests go to /v1/messages in Anthropic's own wire format.

INTRO

response = new_chat(protocol: :anthropic).ask('Hello, in one short sentence.')
body = response.raw.body

puts <<~BASIC
  -- a plain exchange --
  #{response.content}

  endpoint:     #{response.raw.env.url}
  body type:    #{body['type'].inspect}
  content[0]:   #{body['content'].first['type'].inspect}
  stop_reason:  #{body['stop_reason'].inspect}
  usage:        #{body['usage'].inspect}

BASIC

print "-- streaming --\n"
chunks = 0
new_chat(protocol: :anthropic).ask('Count from 1 to 5.') do |chunk|
  chunks += 1
  print chunk.content
end
puts "\n(#{chunks} content_block_delta chunks)\n\n"

tool_chat = new_chat(protocol: :anthropic).with_tools(Weather)
tool_answer = tool_chat.ask('What is the weather in Berlin? Use the tool.')

puts <<~TOOLS
  -- client-side tools --
  #{tool_answer.content}

  The model emitted a tool_use block, RubyLLM ran Weather#execute in this
  process, and the result went back as a tool_result block.
  tool call made: #{tool_chat.messages.any?(&:tool_call?)}

TOOLS

schema_answer = new_chat(protocol: :anthropic).with_schema(SCHEMA).ask('John is 30.')

puts <<~SCHEMA_TRAP
  -- with_schema: the one thing that does NOT work --
  asked for: {"name": String, "age": Integer}
  got back:  #{schema_answer.content.to_s.gsub(/\s+/, ' ')[0, 70]}

  No exception was raised — LM Studio simply ignored the schema. Use the
  default :chat_completions protocol (see examples/04) when you need
  structured output.
SCHEMA_TRAP
