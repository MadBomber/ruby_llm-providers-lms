#!/usr/bin/env ruby
# frozen_string_literal: true

# Which protocol should you use? LM Studio speaks three APIs and this gem
# registers five protocols across them. They are not interchangeable, and
# the differences are easy to trip over — two of them ignore `with_schema`
# without raising, handing you prose where you expected JSON.
#
# This demo asks the same schema-constrained question through every
# protocol and reports what actually came back, on your models and your
# LM Studio build.
#
#   ruby examples/15_protocol_matrix.rb
#
# It makes one request per protocol, so it is the slowest demo here.

require_relative 'common'
require 'json'

ROW = '%-20s %-9s %s'

QUESTION = %(Extract the person from this sentence: John is 30 years old.)

PROTOCOLS = %i[chat_completions responses anthropic native_v0 native_chat].freeze

SCHEMA = {
  type: 'object',
  properties: { name: { type: 'string' }, age: { type: 'integer' } },
  required: %w[name age]
}.freeze

# Returns [verdict, detail] for one protocol without letting a raise or a
# malformed answer stop the sweep.
def probe_schema(protocol)
  response = new_chat(protocol: protocol).with_schema(SCHEMA).ask(QUESTION)
  parsed = JSON.parse(response.content.to_s)
  if parsed['name'] && parsed['age']
    ['honored', response.content.to_s.gsub(/\s+/, ' ')[0, 44]]
  else
    ['IGNORED', "valid JSON, wrong shape: #{parsed.inspect[0, 34]}"]
  end
rescue JSON::ParserError
  ['IGNORED', "not JSON: #{response.content.to_s.gsub(/\s+/, ' ')[0, 34]}"]
rescue StandardError => e
  ['raises', e.class.to_s]
end

puts <<~INTRO
  == Protocol matrix: with_schema across all five protocols (#{MODEL}) ==

  #{format(ROW, 'PROTOCOL', 'VERDICT', 'WHAT CAME BACK')}
INTRO

results = PROTOCOLS.to_h do |protocol|
  verdict, detail = probe_schema(protocol)
  puts format(ROW, protocol, verdict, detail)
  [protocol, verdict]
end

silent = results.select { |_protocol, verdict| verdict == 'IGNORED' }.keys
honored = results.select { |_protocol, verdict| verdict == 'honored' }.keys
raised = results.select { |_protocol, verdict| verdict == 'raises' }.keys

puts <<~SUMMARY

  -- reading this --
  honored: #{honored.join(', ')}
  raises:  #{raised.join(', ')} — tells you it cannot, which is fine
  IGNORED: #{silent.join(', ')} — the dangerous column

  A protocol that raises is safe: you find out immediately. A protocol that
  ignores the schema returns a perfectly ordinary-looking response, so the
  failure surfaces later, in whatever parses it.

  The other axes (streaming, client-side tools, inference stats, stateful
  conversations) are covered per protocol in examples 07, 11, 12 and 13,
  and summarized in the README's protocol table.
SUMMARY
