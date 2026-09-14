# frozen_string_literal: true

require 'spec_helper'

# LM Studio serves Anthropic's Messages API at /v1/messages beside the
# OpenAI and native surfaces. These exercise the same ground the portable
# contract specs cover for the default protocol — a plain exchange, a
# streamed one, and a tool call — but over the Anthropic dialect.
RSpec.describe 'RubyLLM::Chat anthropic protocol', :live do # rubocop:disable RSpec/DescribeClass
  include_context 'with configured RubyLLM'

  let(:weather_tool) do
    Class.new(RubyLLM::Tool) do
      description 'Gets current weather for a location'
      parameter :latitude, description: 'Latitude'
      parameter :longitude, description: 'Longitude'

      def execute(latitude:, longitude:)
        "Current weather at #{latitude}, #{longitude}: 15°C, Wind: 10 km/h"
      end
    end
  end

  each_model(CHAT_MODELS) do |provider, model|
    it "#{provider}/#{model} can have a basic conversation" do
      response = anthropic_chat(model, provider).ask("What's 2 + 2?")

      expect(response.content).to include('4')
      expect(response.role).to eq(:assistant)
      expect(response.tokens.input.to_i).to be_positive
      expect(response.tokens.output.to_i).to be_positive
    end

    it "#{provider}/#{model} reaches the Anthropic messages endpoint" do
      response = anthropic_chat(model, provider).ask('What is the capital of France?')

      expect(response.raw.env.url.to_s).to end_with('/v1/messages')
      expect(response.raw.body['type']).to eq('message')
      expect(response.raw.body['content']).to be_an(Array)
    end

    it "#{provider}/#{model} supports streaming responses" do
      chunks = []
      response = anthropic_chat(model, provider).ask('Count from 1 to 3') { |chunk| chunks << chunk }

      expect(chunks).not_to be_empty
      expect(chunks.map { |chunk| chunk.content.to_s }.join).not_to be_empty
      expect(response.content).not_to be_empty
    end

    it "#{provider}/#{model} can use tools" do
      chat = anthropic_chat(model, provider).with_tools(weather_tool)
      response = chat.ask("What's the weather in Berlin? Use 52.5200, 13.4050.")

      expect(response.content).to include('15')
      expect(chat.messages.any?(&:tool_call?)).to be(true)
    end
  end

  # A context keeps the protocol override off the global configuration.
  def anthropic_chat(model, provider)
    RubyLLM.context { |config| config.lms_protocol = :anthropic }
           .chat(model: model, provider: provider, assume_model_exists: true)
  end
end
