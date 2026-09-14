# frozen_string_literal: true

module RubyLLM
  module Providers
    class LMS < Provider
      # LM Studio serves OpenAI's Responses API at POST /v1/responses, and
      # RubyLLM's stock Responses protocol drives it — except for reasoning,
      # where the two disagree about where the text lives.
      #
      # OpenAI never returns raw reasoning, only an optional summary, so a
      # reasoning item reads:
      #
      #   { type: 'reasoning', summary: [{ type: 'summary_text', text: '...' }] }
      #
      # LM Studio runs the model locally and has nothing to hide, so it
      # returns the reasoning itself, leaving summary empty:
      #
      #   { type: 'reasoning', summary: [], content: [{ type: 'reasoning_text', text: '...' }] }
      #
      # and streams it as `response.reasoning_text.delta` rather than
      # `response.reasoning_summary_text.delta`. Reading only OpenAI's shape
      # loses the reasoning on both paths — the response spends reasoning
      # tokens and `message.thinking` comes back nil.
      class Responses < Protocols::Responses
        REASONING_TEXT_DELTA = 'response.reasoning_text.delta'

        def parse_reasoning_summary(output)
          super || parse_reasoning_text(output)
        end

        def parse_reasoning_text(output)
          texts = output.select { |item| item['type'] == 'reasoning' }.flat_map do |item|
            Array(item['content']).filter_map { |part| part['text'] if part['type'] == 'reasoning_text' }
          end

          texts.empty? ? nil : texts.join("\n")
        end

        def build_chunk(data)
          return super unless data['type'] == REASONING_TEXT_DELTA

          chunk thinking: Thinking.build(text: data['delta'])
        end
      end
    end
  end
end
