# frozen_string_literal: true

module RubyLLM
  module Providers
    class LMS < Provider
      # LM Studio serves OpenAI's Decisions API at POST /v1/decisions for
      # decision models (LM Studio 0.4.26 and later), and RubyLLM's stock
      # Decisions protocol drives it — RubyLLM::Judge and RubyLLM.judge
      # reach it through LMS#judge. Questions go out as an Array and the
      # answers come back as one, each echoing its question's name.
      #
      # RubyLLM 2.1.1 pairs answers with questions by position, which holds
      # only while the server answers in the order it was asked. This reads
      # them by name instead (as RubyLLM's main branch now does), and takes
      # the model id from the request when the response omits it.
      class Decisions < Protocols::OpenAI::Decisions
        def parse_judgment_response(response, questions:)
          body = response.body
          named = body.fetch('answers').to_h { |answer| [answer.fetch('name'), answer] }
          answers = questions.values.to_h do |question|
            [question.name, parse_answer(named.fetch(question.name.to_s), question)]
          end
          RubyLLM::Judgment.new(answers:, model: body['model'] || judged_model_id, raw: response,
                                model_info: @model, tokens: parse_tokens(body['usage']))
        rescue KeyError, NoMethodError, TypeError => e
          raise Error.new("LM Studio Decisions returned an invalid judgment: #{e.message}", response:)
        end

        def judged_model_id
          @model.respond_to?(:id) ? @model.id : @model
        end
      end
    end
  end
end
