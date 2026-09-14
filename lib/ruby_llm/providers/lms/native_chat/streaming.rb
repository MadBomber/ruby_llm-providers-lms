# frozen_string_literal: true

module RubyLLM
  module Providers
    class LMS < Provider
      class NativeChat < RubyLLM::Protocol
        # Streaming methods for LM Studio's native chat API. The server
        # sends named SSE events (message.delta, reasoning.delta, chat.end,
        # plus bookkeeping like prompt_processing.* and model_load.*), each
        # carrying a JSON object with a matching 'type'.
        module Streaming
          # The native stream ends with a `chat.end` event whose `result` is
          # the same object a non-streamed call returns. Streaming leaves the
          # Faraday body as raw SSE text, so the result object replaces it —
          # then `message.raw.body` looks the same either way, response_id
          # and stats included.
          def stream_response(payload, additional_headers = {})
            accumulator = RubyLLM::Protocol::StreamAccumulator.new
            result = nil
            response = stream_events(stream_url, payload, additional_headers) do |data|
              result = data['result'] if data['type'] == 'chat.end' && data['result']
              chunk = build_chunk(data)
              accumulator.add chunk
              yield chunk
            end
            response.env[:body] = result if result
            accumulator.to_message(response)
          end

          def build_chunk(data)
            case data['type']
            when 'message.delta'
              Chunk.new(role: :assistant, content: data['content'])
            when 'reasoning.delta'
              Chunk.new(role: :assistant, content: nil, thinking: Thinking.build(text: data['content']))
            when 'chat.end'
              result_chunk(data['result'] || {})
            else
              Chunk.new(role: :assistant, content: nil)
            end
          end

          def result_chunk(result)
            stats = result['stats'] || {}
            Chunk.new(
              role: :assistant,
              content: nil,
              model: result['model_instance_id'],
              input_tokens: stats['input_tokens'],
              output_tokens: stats['total_output_tokens'],
              thinking_tokens: stats['reasoning_output_tokens'],
              finish_reason: :stop
            )
          end

          def parse_streaming_error(data)
            error = JSON.parse(data)['error']
            [500, error.is_a?(Hash) ? error['message'] : error.to_s]
          rescue JSON::ParserError
            [500, data]
          end
        end
      end
    end
  end
end
