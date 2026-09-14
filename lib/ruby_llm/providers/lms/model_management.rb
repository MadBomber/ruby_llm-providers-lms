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
      module ModelManagement
        NATIVE_V1_MODELS_URL = '../api/v1/models'

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
          connection.post("#{NATIVE_V1_MODELS_URL}/load", payload).body
        end

        # Unloads the loaded instance named +instance_id+ (from #load_model's
        # response or a native listing's 'loaded_instances').
        def unload_model(instance_id)
          connection.post("#{NATIVE_V1_MODELS_URL}/unload", { instance_id: instance_id }).body
        end

        # Asks the server to download +model+ (a model key such as
        # 'qwen/qwen3-4b'). Extra keyword options go into the request as-is.
        def download_model(model, **)
          connection.post("#{NATIVE_V1_MODELS_URL}/download", { model: model, ** }).body
        end
      end
    end
  end
end
