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
        # LM Studio spells its reasoning settings 'off', 'low', 'medium',
        # 'high', 'xhigh', 'on'. RubyLLM's registry speaks OpenAI's
        # vocabulary instead: off is an effort named 'none', and a plain
        # on/off switch is a separate :toggle option rather than an effort.
        # Translating here is what lets Thinking::Controls — and so
        # Chat#with_thinking — find any controls at all.
        REASONING_EFFORT_ALIASES = { 'off' => 'none' }.freeze
        REASONING_TOGGLE = 'on'

        # Rewrites one v1 entry, keeping the v1-only fields (display name,
        # parameter count, size on disk, description, variants, reasoning
        # controls, and the loaded instance's context length and idle TTL)
        # alongside the v0 ones.
        def normalize_v1_detail(model)
          instance = Array(model['loaded_instances']).first
          capabilities = model['capabilities'] || {}
          {
            'type' => normalize_v1_type(model, capabilities),
            'publisher' => model['publisher'],
            'arch' => model['architecture'],
            'compatibility_type' => model['format'],
            'quantization' => model.dig('quantization', 'name'),
            'bits_per_weight' => model.dig('quantization', 'bits_per_weight'),
            'state' => instance ? 'loaded' : 'not-loaded',
            'max_context_length' => model['max_context_length'],
            'capabilities' => normalize_v1_capabilities(capabilities),
            'display_name' => model['display_name'],
            'params_string' => model['params_string'],
            'size_bytes' => model['size_bytes'],
            'description' => model['description'],
            'variants' => model['variants'],
            'selected_variant' => model['selected_variant'],
            'reasoning_options' => normalize_v1_reasoning(capabilities['reasoning']),
            'loaded_context_length' => instance&.dig('config', 'context_length'),
            'remaining_ttl_seconds' => instance&.dig('remaining_ttl_seconds')
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

        # Turns the v1 reasoning block into RubyLLM's reasoning_options: an
        # :effort option listing the graded settings, and a :toggle when the
        # model accepts LM Studio's plain 'on'. Returns nil for a model that
        # reports no reasoning at all, so the key compacts away.
        def normalize_v1_reasoning(reasoning)
          allowed = Array(reasoning && reasoning['allowed_options'])
          return nil if allowed.empty?

          efforts = allowed.reject { |option| option == REASONING_TOGGLE }
                           .map { |option| REASONING_EFFORT_ALIASES.fetch(option, option) }

          options = []
          options << reasoning_effort_option(efforts, reasoning['default']) if efforts.any?
          options << { 'type' => 'toggle' } if allowed.include?(REASONING_TOGGLE)
          options
        end

        # The listing's default is only an effort default when it names one:
        # a model whose default is 'on' is defaulting to its toggle instead.
        def reasoning_effort_option(efforts, default)
          default = REASONING_EFFORT_ALIASES.fetch(default, default)
          option = { 'type' => 'effort', 'values' => efforts }
          option['default'] = default if efforts.include?(default)
          option
        end
      end
    end
  end
end
