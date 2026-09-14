# frozen_string_literal: true

module RubyLLM
  module Providers
    class LMS < Provider
      # Model-listing methods for the LM Studio API integration.
      # Enriches the OpenAI-compatible /v1/models listing with details from
      # LM Studio's native REST API: model type, architecture, quantization,
      # load state, and context length. Both native listings are optional —
      # when neither answers the plain listing still works.
      module Models
        include NativeV1

        NATIVE_V1_MODELS_URL = '../api/v1/models'
        NATIVE_V0_MODELS_URL = '../api/v0/models'
        CAPABILITY_MAP = {
          'tool_use' => 'function_calling',
          'vision' => 'vision'
        }.freeze

        def models_url
          'models'
        end

        def model_capabilities
          %w[streaming structured_output]
        end

        def list_models
          response = @connection.get models_url
          parse_list_models_response(response, @provider.slug, details: native_model_details)
        end

        def parse_list_models_response(response, slug, details: {})
          Array(response.body['data']).map do |model|
            detail = details[model['id']] || {}
            Model.new(
              id: model['id'],
              name: detail['display_name'] || model['id'],
              provider: slug,
              family: detail['arch'] || 'lms',
              created_at: model['created'] ? Time.at(model['created']) : nil,
              context_window: detail['max_context_length'],
              modalities: build_modalities(detail),
              capabilities: build_capabilities(detail),
              pricing: {},
              metadata: build_metadata(model, detail)
            )
          end
        end

        def build_modalities(detail)
          return { input: %w[text], output: %w[embeddings] } if embedding?(detail)

          input = %w[text]
          input << 'image' if vision?(detail)
          { input: input, output: %w[text] }
        end

        def build_capabilities(detail)
          return [] if embedding?(detail)

          reported = Array(detail['capabilities'])
          derived = CAPABILITY_MAP.filter_map { |native, capability| capability if reported.include?(native) }
          derived << 'vision' if vision?(detail) && !derived.include?('vision')
          model_capabilities + derived
        end

        def build_metadata(model, detail)
          {
            owned_by: model['owned_by'],
            publisher: detail['publisher'],
            arch: detail['arch'],
            compatibility_type: detail['compatibility_type'],
            quantization: detail['quantization'],
            state: detail['state'],
            display_name: detail['display_name'],
            params_string: detail['params_string'],
            size_bytes: detail['size_bytes'],
            reasoning_options: detail['reasoning_options'],
            loaded_context_length: detail['loaded_context_length']
          }.compact
        end

        def embedding?(detail)
          detail['type'] == 'embeddings'
        end

        def vision?(detail)
          detail['type'] == 'vlm' || Array(detail['capabilities']).include?('vision')
        end

        private

        # LM Studio serves two native model listings. v1 is the richer one but
        # only exists on newer releases; v0 is served by everything that has a
        # native API at all. Try v1, fall back to v0, then give up quietly.
        def native_model_details
          native_details(NATIVE_V1_MODELS_URL, 'models') { |model| normalize_v1_detail(model) } ||
            native_details(NATIVE_V0_MODELS_URL, 'data') { |detail| detail } ||
            {}
        end

        def native_details(url, key)
          entries = Array(@connection.get(url).body[key])
          entries.to_h { |entry| [entry['key'] || entry['id'], yield(entry)] }
        rescue Error, Faraday::Error => e
          RubyLLM.logger.debug "LM Studio native model details unavailable at #{url} (#{e.message})."
          nil
        end
      end
    end
  end
end
