#!/usr/bin/env ruby
# frozen_string_literal: true

# Structured output: attach a JSON Schema and the model must reply
# with JSON matching it; `response.parsed` gives you the Hash.
#
# Model choice matters on LM Studio: qwen3 models honor json_schema,
# while gpt-oss models mangle it (harmony format) — one reason this
# demo sticks with the default qwen model from common.rb.
#
#   ruby examples/04_structured_output.rb

require_relative 'common'

PERSON_SCHEMA = {
  type: 'object',
  properties: {
    name: { type: 'string' },
    age: { type: 'integer' },
    languages: { type: 'array', items: { type: 'string' } }
  },
  required: %w[name age languages],
  additionalProperties: false
}.freeze

puts <<~INTRO
  == Structured output (#{MODEL}) ==

INTRO

response = new_chat
           .with_schema(PERSON_SCHEMA)
           .ask('Generate a fictional 30-year-old programmer named John who knows Ruby and Rust.')

person = response.parsed

puts <<~RESULT
  raw JSON:  #{response.content}

  parsed Hash:
    name:      #{person['name']}
    age:       #{person['age']} (#{person['age'].class})
    languages: #{person['languages'].join(', ')}
RESULT
