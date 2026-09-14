# frozen_string_literal: true

module RubyLLM
  module Providers
    class LMS < Provider
      # LM Studio serves Anthropic's Messages API alongside the OpenAI and
      # native surfaces, so RubyLLM's stock Anthropic protocol drives it
      # unchanged apart from the request path: Protocols::Anthropic posts to
      # 'v1/messages' against a bare host, while this provider's api_base
      # already ends in /v1. Streaming follows automatically, because the
      # protocol's stream_url delegates to completion_url.
      #
      # Unlike the real Anthropic API, LM Studio wants no credentials and no
      # anthropic-version header.
      #
      #   RubyLLM.configure { |config| config.lms_protocol = :anthropic }
      class AnthropicMessages < Protocols::Anthropic
        # Model listing stays on the OpenAI-compatible /v1/models endpoint
        # that every LM Studio build serves; Anthropic's own listing shape
        # is not part of what LM Studio exposes.
        include LMS::Models

        def completion_url
          'messages'
        end
      end
    end
  end
end
