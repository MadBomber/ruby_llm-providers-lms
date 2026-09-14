# frozen_string_literal: true

module RubyLLM
  module Providers
    class LMS < Provider
      # Model-management methods backed by LM Studio's native REST API
      # (`/api/v1/models` and friends, reached relative to the OpenAI-compatible
      # API base). They control what is in memory and on disk on the server:
      # listing downloaded models with their loaded instances, loading a model
      # (optionally with a context-length override), unloading an instance,
      # and downloading a new model.
      #
      # Every write here is sent non-idempotent. RubyLLM's Faraday stack
      # retries a POST that times out or loses its connection, and none of
      # these are safe to replay: LM Studio answers a second load of a
      # resident model by starting a second instance, so a slow load that
      # timed out would end up holding the weights in memory twice.
      module ModelManagement
        # Every downloaded model with its native details (architecture,
        # quantization, capabilities, loaded_instances, ...), as an Array of
        # Hashes straight from the server.
        def native_models
          Array(connection.get(NATIVE_V1_MODELS_URL).body['models'])
        end

        # The subset of #native_models with at least one loaded instance.
        def loaded_models
          native_models.select { |model| Array(model['loaded_instances']).any? }
        end

        # Loads +model+ into memory. Returns the server's response Hash,
        # whose 'instance_id' is what #unload_model takes. Extra keyword
        # options go into the request as-is (the server rejects unknown keys).
        def load_model(model, context_length: nil, **options)
          payload = { model: model, context_length: context_length, **options }.compact
          post_model_action('load', payload)
        end

        # Unloads the loaded instance named +instance_id+ (from #load_model's
        # response or a native listing's 'loaded_instances').
        def unload_model(instance_id)
          post_model_action('unload', { instance_id: instance_id })
        end

        # Asks the server to download +model+ (a model key such as
        # 'qwen/qwen3-4b'). Extra keyword options go into the request as-is.
        def download_model(model, **)
          post_model_action('download', { model: model, ** })
        end

        private

        def post_model_action(action, payload)
          connection.post("#{NATIVE_V1_MODELS_URL}/#{action}", payload, idempotent: false).body
        end
      end
    end
  end
end
