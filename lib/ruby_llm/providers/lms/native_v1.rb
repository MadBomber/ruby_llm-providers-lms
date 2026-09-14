# frozen_string_literal: true

module RubyLLM
  module Providers
    class LMS < Provider
      # Rewrites entries from LM Studio's native v1 model listing
      # (GET /api/v1/models) into the vocabulary of the older v0 listing,
      # which is what LMS::Models reads. v1 states things differently —
      # capabilities as a Hash of flags rather than an Array of names,
      # vision as a capability rather than a model type, load state as a
      # list of running instances — and carries several fields v0 has no
      # equivalent for.
      module NativeV1
        # Rewrites one v1 entry, keeping the v1-only fields (display name,
        # parameter count, size on disk, reasoning effort options, and the
        # loaded instance's context length) alongside the v0 ones.
        def normalize_v1_detail(model)
          instance = Array(model['loaded_instances']).first
          capabilities = model['capabilities'] || {}
          {
            'type' => normalize_v1_type(model, capabilities),
            'publisher' => model['publisher'],
            'arch' => model['architecture'],
            'compatibility_type' => model['format'],
            'quantization' => model.dig('quantization', 'name'),
            'state' => instance ? 'loaded' : 'not-loaded',
            'max_context_length' => model['max_context_length'],
            'capabilities' => normalize_v1_capabilities(capabilities),
            'display_name' => model['display_name'],
            'params_string' => model['params_string'],
            'size_bytes' => model['size_bytes'],
            'reasoning_options' => capabilities.dig('reasoning', 'allowed_options'),
            'loaded_context_length' => instance&.dig('config', 'context_length')
          }.compact
        end

        # v1 reports only 'llm' and 'embedding' and states vision as a
        # capability; v0 spells those 'embeddings' and 'vlm'.
        def normalize_v1_type(model, capabilities)
          return 'embeddings' if model['type'] == 'embedding'
          return 'vlm' if capabilities['vision']

          model['type']
        end

        # v1 reports capabilities as a Hash of flags, v0 as an Array of names.
        def normalize_v1_capabilities(capabilities)
          names = []
          names << 'vision' if capabilities['vision']
          names << 'tool_use' if capabilities['trained_for_tool_use']
          names
        end
      end
    end
  end
end
