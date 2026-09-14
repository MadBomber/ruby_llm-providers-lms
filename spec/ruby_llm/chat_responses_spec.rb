# frozen_string_literal: true

require 'spec_helper'

# LM Studio serves OpenAI's Responses API at POST /v1/responses, and the gem
# registers RubyLLM's stock Responses protocol against it. The protocol had no
# behavioural coverage at all — only an assertion that it was registered — even
# though it is the endpoint LM Studio is actively developing.
RSpec.describe 'RubyLLM::Chat responses protocol', :live do # rubocop:disable RSpec/DescribeClass
  include_context 'with configured RubyLLM'

  def responses_chat(model, provider)
    RubyLLM.context { |config| config.lms_protocol = :responses }
           .chat(model: model, provider: provider, assume_model_exists: true)
  end

  each_model(CHAT_MODELS) do |provider, model|
    it "#{provider}/#{model} reaches the responses endpoint" do
      response = responses_chat(model, provider).ask("What's 2 + 2?")

      expect(response.content).to include('4')
      expect(response.role).to eq(:assistant)
      expect(response.raw.env.url.path).to end_with('/v1/responses')
      expect(response.tokens.input.to_i).to be_positive
    end

    it "#{provider}/#{model} supports streaming responses" do
      chunks = []
      response = responses_chat(model, provider).ask('Count from 1 to 3') { |chunk| chunks << chunk }

      expect(chunks).not_to be_empty
      expect(chunks.first).to be_a(RubyLLM::Chunk)
      expect(response.content).not_to be_empty
    end

    it "#{provider}/#{model} handles a multi-turn conversation" do
      chat = responses_chat(model, provider)

      chat.ask('My name is Dewayne. Reply with only: noted')
      expect(chat.ask('What is my name? Answer with just the name.').content).to include('Dewayne')
    end
  end

  # LM Studio returns the reasoning itself here rather than OpenAI's summary,
  # which the stock protocol would have dropped.
  each_model(REASONING_MODELS) do |provider, model|
    it "#{provider}/#{model} returns reasoning text" do
      response = responses_chat(model, provider)
                 .with_thinking(effort: :low)
                 .ask('What is 2 + 2? Think briefly.')

      expect(response.content).to include('4')
      expect(response.thinking&.text).not_to be_nil
      expect(response.tokens.thinking.to_i).to be_positive
    end

    it "#{provider}/#{model} streams reasoning as thinking chunks" do
      chunks = []
      response = responses_chat(model, provider)
                 .with_thinking(effort: :low)
                 .ask('What is 3 + 3? Think briefly.') { |chunk| chunks << chunk }

      expect(chunks.count(&:thinking)).to be_positive
      expect(response.thinking&.text).not_to be_nil
    end
  end

  each_model(TOOL_MODELS) do |provider, model|
    it "#{provider}/#{model} runs client-side tools" do
      tool = Class.new(RubyLLM::Tool) do
        description 'Gets the current temperature for a city'
        parameter :city, description: 'City name'

        def execute(city:) = "It is 15°C in #{city}."
      end

      chat = responses_chat(model, provider).with_tools(tool)
      response = chat.ask("What's the temperature in Berlin?")

      expect(response.content).to include('15')
      expect(chat.messages.any?(&:tool_call?)).to be(true)
    end
  end
end
