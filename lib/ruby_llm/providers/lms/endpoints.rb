# frozen_string_literal: true

module RubyLLM
  module Providers
    # Endpoint paths for the LM Studio API integration. LM Studio serves its
    # native REST API beside the OpenAI-compatible base rather than under it,
    # so these are spelled relative to an api_base ending in /v1.
    #
    # They live on the provider rather than in the modules that use them
    # because two of those modules are mixed into different objects — Models
    # into the protocols, ModelManagement into the provider — and a path
    # spelled twice is a path that can drift.
    class LMS < Provider
      NATIVE_V1_MODELS_URL = '../api/v1/models'
      NATIVE_V0_MODELS_URL = '../api/v0/models'
    end
  end
end
