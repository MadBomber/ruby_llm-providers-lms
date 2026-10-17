# frozen_string_literal: true

module RubyLLM
  module Providers
    class LMS < Provider
      # LM Studio also serves the Jev (TypeSafe) System One API at
      # POST /v1/systemone for decision models. Questions go out as a Hash
      # keyed by name and the answers come back keyed the same way, so the
      # stock protocol needs only two changes:
      #
      # - The path. It spells it 'v1/systemone' for TypeSafe's bare host,
      #   which beside an api_base ending in /v1 would land on
      #   /v1/v1/systemone.
      # - Images. The stock protocol refuses them; LM Studio reads them from a
      #   top-level `images` array of inline base64 data URLs. (A
      #   Responses-style content array in `state` is accepted but its images
      #   are ignored -- the answer doesn't change with the picture.) `state`
      #   is required even then, so an image judged without text sends an
      #   empty one.
      #
      # Select it over Decisions with `config.lms_judgment_protocol =
      # :system_one`.
      class SystemOne < Protocols::SystemOne
        def judgment_url
          'systemone'
        end

        def render_judgment_payload(input, with: [], **)
          payload = super(input, with: [], **)
          return payload if with.empty?

          payload.merge(state: payload[:state] || '', images: render_images(with))
        end

        def render_images(attachments)
          attachments.map do |attachment|
            raise UnsupportedAttachmentError, attachment.mime_type unless attachment.image?

            attachment.for_llm
          end
        end
      end
    end
  end
end
