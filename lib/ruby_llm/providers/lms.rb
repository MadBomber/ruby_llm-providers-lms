# frozen_string_literal: true

require 'ruby_llm'
require 'ruby_llm/providers/lms/version'
require 'ruby_llm/providers/lms/connection_guard'
require 'ruby_llm/providers/lms/native_v1'
require 'ruby_llm/providers/lms/models'
require 'ruby_llm/providers/lms/anthropic_messages'
require 'ruby_llm/providers/lms/model_management'
require 'ruby_llm/providers/lms/native_chat/conversation'
require 'ruby_llm/providers/lms/native_chat/streaming'
require 'ruby_llm/providers/lms/native_chat'

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

      # LM Studio's native v0 chat endpoint. Request and response shapes
      # match the OpenAI-compatible endpoint exactly — streaming and tool
      # calls included — but the response says more about the inference:
      # it fills in the `stats` block that /v1/chat/completions leaves
      # empty (tokens per second, time to first token, generation time,
      # stop reason) and adds `model_info` and `runtime`. RubyLLM has no
      # field for any of it, so it arrives through Message#raw:
      #
      #   RubyLLM.configure { |config| config.lms_protocol = :native_v0 }
      #   response = RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms).ask('Hello')
      #   response.raw.body['stats']['tokens_per_second'] # => 251.5
      class NativeChatCompletions < ChatCompletions
        def completion_url
          '../api/v0/chat/completions'
        end
      end

      protocol :chat_completions, ChatCompletions
      protocol :responses, Protocols::Responses
      protocol :native_chat, NativeChat
      protocol :native_v0, NativeChatCompletions
      protocol :anthropic, AnthropicMessages

      include ModelManagement

      def initialize(config)
        super
        @connection = ConnectionGuard.new(@connection)
      end

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
