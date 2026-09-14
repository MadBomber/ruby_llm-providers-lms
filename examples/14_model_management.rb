#!/usr/bin/env ruby
# frozen_string_literal: true

# Model management over the native REST API (/api/v1/models/...). The
# provider can list what is downloaded, see what is resident in memory, and
# load or unload instances without shelling out to `lms`.
#
# This demo loads the smallest model on your server and unloads it again,
# leaving things as it found them. Note that if auto-evict is on (the LM
# Studio default) loading any model may evict one already resident — see
# "Model lifecycle" in the README.
#
# download_model is shown but not called: it would pull gigabytes.
#
#   ruby examples/14_model_management.rb

require_relative 'common'

provider = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config)

catalog = provider.native_models
resident = provider.loaded_models

def describe(model)
  size = model['size_bytes']
  human = size ? "#{(size / 1_073_741_824.0).round(2)} GB" : '?'
  "#{model['key']} (#{model['params_string'] || '?'}, #{human})"
end

puts <<~CATALOG
  == Model management (#{RubyLLM.config.lms_api_base}) ==

  -- what is downloaded --
  #{catalog.length} models on disk, smallest first:
  #{catalog.sort_by { |model| model['size_bytes'] || 0 }.first(3).map { |model| "  #{describe(model)}" }.join("\n")}

  -- what is in memory right now --
  #{resident.empty? ? '  (nothing loaded)' : resident.map { |model| "  #{describe(model)}" }.join("\n")}

CATALOG

# Try the smallest unloaded models first. A catalog can hold entries that
# announce themselves as LLMs but will not load — control-vector artifacts,
# for instance — so step past anything the server refuses rather than
# giving up on the first failure.
candidates = catalog.reject { |model| Array(model['loaded_instances']).any? }
                    .sort_by { |model| model['size_bytes'] || Float::INFINITY }

loaded = nil
candidates.each do |model|
  puts "-- loading #{model['key']} --"
  loaded = provider.load_model(model['key'], context_length: 4096)
  break
rescue RubyLLM::Error => e
  puts "   server refused it (#{e.class}) — trying the next one"
end

if loaded.nil?
  puts "\nNo model on this server could be loaded; nothing further to show."
  exit
end

instance_id = loaded['instance_id']

puts <<~LOADED
  load_model ->  #{loaded.inspect}

  instance_id is what unload_model takes. Loading a model that is already
  resident starts a second instance (...:2), so keep the id you were given.

  now resident:  #{provider.loaded_models.map { |model| model['key'] }.join(', ')}

LOADED

puts <<~UNLOADED
  -- unloading it again --
  unload_model -> #{provider.unload_model(instance_id).inspect}
  now resident:   #{provider.loaded_models.map { |model| model['key'] }.join(', ')}

  -- not called here --
  provider.download_model('qwen/qwen3-4b')   # fetches a model onto disk

  Note: ttl is not a load option on the native API. Set idle TTL per
  request through the OpenAI endpoints (examples/09) or `lms load --ttl`.
UNLOADED
