#!/usr/bin/env ruby
# frozen_string_literal: true

# The native REST API's stateful chat (POST /api/v1/chat), reached with the
# :native_chat protocol. This is the one dialect that is not OpenAI-shaped,
# and it trades features for capabilities the other protocols cannot express:
#
#   gained   server-stored conversations (only the new turn goes over the
#            wire), reasoning control and separated thinking output,
#            per-request context length, server-side MCP tools
#   given up client-side tools (with_tools raises), structured output
#            (with_schema raises), and the LM Studio request extras
#            (ttl, draft_model, ...) — the server rejects unknown keys
#
#   ruby examples/13_native_chat.rb
#
# Reasoning needs a model that emits reasoning items; set LMS_REASONING_MODEL
# to one (gpt-oss works well) or that section is skipped.

require_relative 'common'
require 'json'

REASONING_MODEL = ENV.fetch('LMS_REASONING_MODEL', 'openai/gpt-oss-20b')

puts <<~INTRO
  == Native stateful chat (#{MODEL}) ==
  Requests go to /api/v1/chat, not /v1/chat/completions.

INTRO

chat = new_chat(protocol: :native_chat)
first = chat.ask('Remember the number 42. Reply with just: OK')
second = chat.ask('What number did I ask you to remember?')

second_request = JSON.parse(second.raw.env.request_body)

puts <<~STATEFUL
  -- stateful conversation --
  turn 1: #{first.content.to_s.gsub(/\s+/, ' ')[0, 60]}
  turn 2: #{second.content.to_s.gsub(/\s+/, ' ')[0, 60]}

  Turn 1 was stored server-side and came back with an id:
    response_id:          #{first.raw.body['response_id'].inspect}

  Turn 2 did not replay the history. It sent only the new message and
  pointed at that id:
    input:                #{second_request['input'].inspect}
    previous_response_id: #{second_request['previous_response_id'].inspect}

  -- performance stats, folded into response.tokens --
  stats:  #{first.raw.body['stats'].inspect[0, 96]}
  tokens: in=#{first.tokens.input} out=#{first.tokens.output}

STATEFUL

reasoning = new_chat(model: REASONING_MODEL, protocol: :native_chat)
            .with_thinking(effort: :low)
            .ask('What is 17 * 23? Think briefly.')
thinking = reasoning.thinking&.text

if thinking.to_s.empty?
  puts <<~NO_REASONING
    -- reasoning control --
    #{REASONING_MODEL} returned no reasoning items. Set LMS_REASONING_MODEL
    to a model that emits them (gpt-oss) to see this section.

  NO_REASONING
else
  puts <<~REASONING
    -- reasoning control (#{REASONING_MODEL}, effort: :low) --
    answer:   #{reasoning.content.to_s.gsub(/\s+/, ' ')[0, 60]}
    thinking: #{thinking.gsub(/\s+/, ' ')[0, 80]}

    Reasoning arrives separated from the answer rather than embedded in it,
    and is counted on its own: #{reasoning.tokens.thinking} thinking tokens.

  REASONING
end

begin
  new_chat(protocol: :native_chat).with_schema('type' => 'object').ask('John is 30.')
  puts '-- limitations --\nwith_schema unexpectedly succeeded.'
rescue StandardError => e
  puts <<~LIMITS
    -- limitations, stated honestly --
    with_schema raises here: #{e.class}

    Unlike the Anthropic and Responses protocols, which ignore a schema
    silently, this one tells you. For structured output or client-side
    tools use :chat_completions; for stats without giving anything up
    use :native_v0 (examples/11).
  LIMITS
end
