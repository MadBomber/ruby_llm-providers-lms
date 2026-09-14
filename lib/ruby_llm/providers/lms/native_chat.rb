# frozen_string_literal: true

module RubyLLM
  module Providers
    class LMS < Provider
      # Chat protocol for LM Studio's native REST API (`POST /api/v1/chat`).
      # Select it with `protocol: :native_chat` on the chat or
      # `config.lms_protocol = :native_chat`.
      #
      # The native API is stateful: LM Studio stores each response
      # server-side and continues a conversation from a `response_id`
      # rather than replaying role-tagged history. This protocol makes
      # RubyLLM's ordinary multi-turn Chat work on top of that: each
      # request sends only the messages newer than the last assistant
      # response and points `previous_response_id` at it. The response's
      # id, performance stats, and server-side tool calls all ride on
      # `message.raw.body`.
      #
      # Native-only capabilities reach the request through
      # `with_provider_options`: `integrations:` (MCP plugins or ephemeral
      # MCP servers the server runs itself), `context_length:`, and
      # `store: false` (which trades multi-turn continuity for privacy).
      # Client-side RubyLLM tools and structured output are not part of
      # this wire format — the :chat_completions protocol serves those.
      class NativeChat < RubyLLM::Protocol
        include LMS::Models
        include RubyLLM::Protocols::ChatCompletions::Embeddings
        include NativeChat::Conversation
        include NativeChat::Streaming

        def completion_url
          '../api/v1/chat'
        end

        def stream_url
          completion_url
        end

        # rubocop:disable-next Lint/UnusedMethodArgument
        def render_payload(messages, tools:, temperature:, model:, stream: false, max_output_tokens: nil,
                           schema: nil, thinking: nil, citations: false, caching: nil, tool_prefs: nil)
          ensure_supported!(tools: tools, schema: schema)
          previous_response_id, pending = split_conversation(messages.reject { |msg| msg.role == :system })

          payload = { model: model.id, input: render_input(pending), stream: stream }
          system_prompt = system_prompt_from(messages)
          payload[:system_prompt] = system_prompt if system_prompt
          payload[:previous_response_id] = previous_response_id if previous_response_id
          payload[:temperature] = temperature unless temperature.nil?
          payload[:max_output_tokens] = max_output_tokens unless max_output_tokens.nil?
          reasoning = resolve_reasoning(thinking)
          payload[:reasoning] = reasoning if reasoning
          payload
        end

        def parse_completion_body(data, raw:)
          raise Error.new(error_message(data), response: raw) if data['error']

          output = Array(data['output'])
          raise Error.new('LM Studio returned no output items', response: raw) if output.empty?

          stats = data['stats'] || {}
          Message.new(
            role: :assistant,
            content: output_text(output),
            thinking: Thinking.build(text: reasoning_text(output)),
            input_tokens: stats['input_tokens'],
            output_tokens: stats['total_output_tokens'],
            thinking_tokens: stats['reasoning_output_tokens'],
            finish_reason: :stop,
            model: data['model_instance_id'],
            raw: raw
          )
        end

        # Maps RubyLLM thinking options onto the native `reasoning` setting
        # ('off' | 'low' | 'medium' | 'high' | 'on'; models accept a subset).
        def resolve_reasoning(thinking)
          return nil unless thinking
          return 'off' if thinking.respond_to?(:disabled?) && thinking.disabled?

          effort = thinking.respond_to?(:effort) ? thinking.effort : nil
          effort ? effort.to_s : 'on'
        end

        def ensure_supported!(tools:, schema:)
          if tools&.any?
            raise Error,
                  "LM Studio's native chat API does not run client-side tools; use the " \
                  ':chat_completions protocol for RubyLLM tools, or have the server run MCP ' \
                  'tools with with_provider_options(integrations: [...])'
          end
          return unless schema

          raise Error,
                "LM Studio's native chat API does not support structured output; " \
                'use the :chat_completions protocol for with_schema'
        end

        def error_message(data)
          error = data['error']
          error.is_a?(Hash) ? error['message'] : error.to_s
        end

        def output_text(output)
          text = output.filter_map { |item| item['content'] if item['type'] == 'message' }.join
          text.empty? ? nil : text
        end

        def reasoning_text(output)
          output.filter_map { |item| item['content'] if item['type'] == 'reasoning' }.join
        end
      end
    end
  end
end
