# frozen_string_literal: true

require 'spec_helper'

# The OpenAI-compatible endpoint does carry reasoning, contrary to what this
# gem used to claim: LM Studio accepts `reasoning_effort` on
# /v1/chat/completions and answers with `reasoning_content` alongside
# `completion_tokens_details.reasoning_tokens`, which RubyLLM's stock
# ChatCompletions protocol already reads into Message#thinking.
#
# Note the two surfaces spell the vocabulary differently:
#   /v1/chat/completions  none, minimal, low, medium, high, xhigh
#   /api/v1/chat          off, low, medium, high, xhigh, on
RSpec.describe 'RubyLLM::Chat reasoning', :live do # rubocop:disable RSpec/DescribeClass
  include_context 'with configured RubyLLM'

  each_model(REASONING_MODELS) do |provider, model|
    it "#{provider}/#{model} separates reasoning from content" do
      response = RubyLLM.chat(model: model, provider: provider, assume_model_exists: true)
                        .with_thinking(effort: :low)
                        .ask('What is 2 + 2? Answer with just the number.')

      expect(response.content).to include('4')
      expect(response.thinking&.text).not_to be_nil
      expect(response.tokens.thinking.to_i).to be_positive
    end
  end

  # with_thinking(false) resolves against the registry, so this only works if
  # the catalog carries the off control the server reports. It is the call
  # that used to raise ArgumentError on every LM Studio model.
  each_model(REASONING_OFF_MODELS) do |provider, model|
    it "#{provider}/#{model} spends no reasoning tokens when thinking is off" do
      response = RubyLLM.chat(model: model, provider: provider, assume_model_exists: true)
                        .with_thinking(false)
                        .ask('What is 2 + 2? Answer with just the number.')

      expect(response.content).to include('4')
      expect(response.tokens.thinking.to_i).to be_zero
    end

    it "#{provider}/#{model} enables thinking with no arguments at all" do
      response = RubyLLM.chat(model: model, provider: provider, assume_model_exists: true)
                        .with_thinking
                        .ask('What is 2 + 2? Answer with just the number.')

      expect(response.content).to include('4')
      expect(response.thinking&.text).not_to be_nil
    end
  end

  # The catalog half of the fix: what the server reports has to arrive as
  # something Thinking::Controls can actually read.
  it 'lms reports usable reasoning controls in the live model listing' do
    models = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config).list_models
    reasoning_models = models.select { |model| model.supports?(:reasoning) }

    expect(reasoning_models).not_to be_empty
    expect(reasoning_models).to all(satisfy { |model| model.reasoning_options.any? })

    efforts = reasoning_models.flat_map { |model| model.reasoning_option_values(:effort) }.uniq
    expect(efforts - %w[none minimal low medium high xhigh]).to be_empty
  end
end
