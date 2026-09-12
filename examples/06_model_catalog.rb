#!/usr/bin/env ruby
# frozen_string_literal: true

# Model catalog — the LMS provider's signature feature. It fetches the
# OpenAI-compatible /v1/models list and enriches every entry with
# details from LM Studio's native REST API (/api/v0/models):
# architecture, quantization, load state, context length, and
# tool/vision capabilities. Enrichment degrades gracefully — on an
# LM Studio build without the native endpoint you still get the ids.
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
puts <<~SUMMARY

  -- notes --
  #{loaded.length} currently loaded: #{loaded.map(&:id).join(', ')}
  Chatting needs no catalog: any id LM Studio knows is loaded
  just-in-time when you first ask.
SUMMARY
