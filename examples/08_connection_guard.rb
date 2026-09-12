#!/usr/bin/env ruby
# frozen_string_literal: true

# Connection guard: refused connections normally bypass RubyLLM's
# error middleware (it only maps HTTP status codes), so a stopped
# server would surface as a raw Faraday::ConnectionFailed. The LMS
# provider wraps its connection so you get a RubyLLM::Error with a
# hint to run `lms server start` instead.
#
# This demo points at a port where nothing listens, on purpose.
#
#   ruby examples/08_connection_guard.rb

require_relative 'common'

RubyLLM.configure { |config| config.lms_api_base = 'http://localhost:59999/v1' }

puts <<~INTRO
  == Connection guard ==
  Asking a server that isn't there (#{RubyLLM.config.lms_api_base})...

INTRO

begin
  new_chat.ask('Hello?')
  puts 'Unexpectedly got an answer — is something listening on 59999?'
rescue RubyLLM::Error => e
  puts <<~RESCUED
    Rescued a plain RubyLLM::Error (#{e.class}), not a raw Faraday one:

      #{e.message}
  RESCUED
end
