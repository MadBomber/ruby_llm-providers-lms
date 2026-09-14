#!/usr/bin/env ruby
# frozen_string_literal: true

# Model catalog — the LMS provider's signature feature. It fetches the
# OpenAI-compatible /v1/models list and enriches every entry from
# LM Studio's native REST API: architecture, quantization, load state,
# context length, and tool/vision capabilities.
#
# There are two native listings. /api/v1/models is the richer one and is
# tried first; /api/v0/models is the fallback for builds that do not
# serve v1. Enrichment degrades gracefully all the way down — with
# neither endpoint available you still get the ids.
#
# Unlike the models.json packaged with the gem (a machine-specific
# sample), `list_models` hits your live server every time.
#
#   ruby examples/06_model_catalog.rb

require_relative 'common'

provider = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config)
models = provider.list_models

puts <<~INTRO
  == Live model catalog (#{RubyLLM.config.lms_api_base}) ==
  #{models.length} models on this server

INTRO

format_string = '%-45s %-12s %-8s %-10s %8s  %s'
puts format(format_string, 'ID', 'ARCH', 'QUANT', 'STATE', 'CONTEXT', 'CAPABILITIES')

models.each do |model|
  puts format(format_string,
              model.id[0, 45],
              model.metadata[:arch] || '-',
              model.metadata[:quantization] || '-',
              model.metadata[:state] || '-',
              model.context_window || '-',
              model.capabilities.join(','))
end

loaded = models.select { |model| model.metadata[:state] == 'loaded' }

# Fields only the v1 listing reports. On a v0-only server these are all
# absent and the table above is everything the native API offers.
detailed = models.find { |model| model.metadata[:params_string] } || models.first
extras = detailed.metadata.slice(:display_name, :params_string, :size_bytes,
                                 :reasoning_options, :loaded_context_length)
extras_format = '%-22s %s'
extra_lines = extras.map { |key, value| format(extras_format, "#{key}:", value.inspect) }

puts <<~SUMMARY

  -- what the v1 listing adds, for #{detailed.id} --
  #{format(extras_format, 'Model#name:', detailed.name)}
  #{extras.empty? ? 'nothing — this server answers only /api/v0/models' : extra_lines.join("\n")}

  -- notes --
  #{loaded.length} currently loaded: #{loaded.map(&:id).join(', ')}
  Chatting needs no catalog: any id LM Studio knows is loaded
  just-in-time when you first ask.
SUMMARY
