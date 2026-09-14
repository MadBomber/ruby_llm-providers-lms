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
      # Model listing and embeddings are not this protocol's business: both
      # stay on the OpenAI-compatible endpoints LM Studio serves on the same
      # port, routed there by the provider itself.
      #
      #   RubyLLM.configure { |config| config.lms_protocol = :anthropic }
      class AnthropicMessages < Protocols::Anthropic
        def completion_url
          'messages'
        end
      end
    end
  end
end
