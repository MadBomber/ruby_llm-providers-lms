# frozen_string_literal: true

module RubyLLM
  module Providers
    class LMS < Provider
      class NativeChat < RubyLLM::Protocol
        # Maps RubyLLM's role-tagged message history onto the native API's
        # stateful conversation model: system messages become the
        # system_prompt, the last assistant response supplies a
        # previous_response_id to continue from, and only the messages
        # after it are rendered as input.
        module Conversation
          RESPONSE_ID_PATTERN = /"response_id"\s*:\s*"(resp_[0-9a-f]+)"/

          # What an assistant message has to carry for the next turn to
          # continue from it. It goes on Message#raw_content because that is
          # the slot RubyLLM persists and rebuilds (see
          # ActiveRecord::MessageMethods#to_llm) — Message#raw holds a
          # Faraday::Response that lasts only as long as the request, so a
          # chat reloaded from the database would have nothing to continue
          # from. The stock Mistral and Gemini stateful protocols use
          # raw_content the same way.
          def conversation_state(data)
            response_id = data['response_id']
            { 'response_id' => response_id } if response_id
          end

          # The `response_id` of the stored server-side response +message+
          # came from, or nil. Prefers the persisted copy, then the parsed
          # response body, then raw SSE text.
          def response_id_from(message)
            return nil unless message.role == :assistant

            stored_response_id(message.raw_content) || stored_response_id(message.raw&.body)
          end

          def stored_response_id(source)
            case source
            when Hash then source['response_id']
            when String then source.scan(RESPONSE_ID_PATTERN).flatten.last
            end
          end

          def system_prompt_from(messages)
            prompts = messages.select { |msg| msg.role == :system }.map { |msg| msg.content.to_s }
            prompts.empty? ? nil : prompts.join("\n\n")
          end

          # Splits the non-system conversation at the last assistant message
          # whose response_id is known: that id continues the stored chat and
          # only the messages after it are sent as input.
          def split_conversation(conversation)
            last_continuable = conversation.rindex { |msg| response_id_from(msg) }
            return [nil, ensure_replayable!(conversation)] unless last_continuable

            [response_id_from(conversation[last_continuable]),
             ensure_replayable!(conversation[(last_continuable + 1)..])]
          end

          def ensure_replayable!(messages)
            return messages unless messages.any? { |msg| msg.role == :assistant }

            raise Error,
                  "LM Studio's native chat API cannot replay assistant history; it continues " \
                  'stored conversations by response_id. Keep store enabled (the default) so ' \
                  'responses carry one, or use the :chat_completions protocol.'
          end

          def render_input(messages)
            parts = messages.flat_map { |msg| input_parts(msg) }
            return parts.first[:content] if parts.length == 1 && parts.first[:type] == 'text'

            parts
          end

          def input_parts(msg)
            parts = []
            content = msg.content.to_s
            parts << { type: 'text', content: content } unless content.empty?
            msg.attachments.each { |attachment| parts << input_image_part(attachment) }
            parts
          end

          def input_image_part(attachment)
            raise UnsupportedAttachmentError, attachment.mime_type unless attachment.type == :image

            { type: 'image', data_url: attachment.url? ? attachment.source.to_s : attachment.for_llm }
          end
        end
      end
    end
  end
end
