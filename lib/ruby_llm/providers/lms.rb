# frozen_string_literal: true

require 'ruby_llm'
require 'ruby_llm/providers/lms/models'

module RubyLLM
  module Providers
    # LM Studio API integration. Talks to the local LM Studio server
    # (`lms server start`) through its OpenAI-compatible endpoints.
    # Works out of the box against http://localhost:1234/v1 — no API key
    # required.
    class LMS < Provider
      DEFAULT_API_BASE = 'http://localhost:1234/v1'

      # LM Studio's dialect of the Chat Completions API.
      class ChatCompletions < Protocols::ChatCompletions
        include LMS::Models
      end

      protocol :chat_completions, ChatCompletions
      protocol :responses, Protocols::Responses

      def api_base
        @config.lms_api_base || DEFAULT_API_BASE
      end

      def headers
        return {} unless @config.lms_api_key

        { 'Authorization' => "Bearer #{@config.lms_api_key}" }
      end

      class << self
        def display_name
          'LM Studio'
        end

        def configuration_options
          %i[lms_api_base lms_api_key]
        end

        def configuration_requirements
          []
        end

        def local?
          true
        end
      end
    end
  end
end

RubyLLM::Provider.register :lms, RubyLLM::Providers::LMS,
                           models: File.expand_path('../../../models.json', __dir__)
