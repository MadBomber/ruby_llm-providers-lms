# frozen_string_literal: true

module RubyLLM
  module Providers
    class LMS < Provider
      # Model-listing methods for the LM Studio API integration.
      # Enriches the OpenAI-compatible /v1/models listing with details from
      # LM Studio's native REST API (/api/v0/models): model type, architecture,
      # quantization, load state, and context length. The native endpoint is
      # optional — when it is unavailable the plain listing still works.
      module Models
        NATIVE_MODELS_URL = '../api/v0/models'
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
              name: model['id'],
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
            state: detail['state']
          }.compact
        end

        def embedding?(detail)
          detail['type'] == 'embeddings'
        end

        def vision?(detail)
          detail['type'] == 'vlm' || Array(detail['capabilities']).include?('vision')
        end

        private

        def native_model_details
          Array(@connection.get(NATIVE_MODELS_URL).body['data']).to_h { |detail| [detail['id'], detail] }
        rescue Error, Faraday::Error => e
          RubyLLM.logger.debug "LM Studio native model details unavailable (#{e.message})."
          {}
        end
      end
    end
  end
end
