#!/usr/bin/env ruby
# frozen_string_literal: true

# Tools (function calling): the model decides to call your Ruby code,
# RubyLLM executes it, and the model folds the result into its answer.
# Works with any LM Studio model that reports the `tool_use`
# capability (`lms ls` or examples/06_model_catalog.rb shows which).
#
#   ruby examples/03_tools.rb

require_relative 'common'

# A fake weather service. Real tools would hit an API or a database;
# the shape is the same: declared parameters in, string result out.
class Weather < RubyLLM::Tool
  description 'Gets current weather for a location'
  parameter :latitude, description: 'Latitude'
  parameter :longitude, description: 'Longitude'

  def execute(latitude:, longitude:)
    "Current weather at #{latitude}, #{longitude}: 15°C, wind 10 km/h"
  end
end

puts <<~INTRO
  == Tools (#{MODEL}) ==

INTRO

chat = new_chat.with_tools(Weather)
response = chat.ask("What's the weather in Berlin? Use 52.5200, 13.4050.")

puts response.content

tool_turns = chat.messages.count(&:tool_call?)
puts <<~SUMMARY

  -- behind the scenes --
  The conversation took #{chat.messages.length} messages,
  #{tool_turns} of them tool calls made by the model.
SUMMARY
