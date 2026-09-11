# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::LMS::NativeChat, :live do
  include_context 'with configured RubyLLM'

  def native_chat(model, provider)
    RubyLLM.chat(model: model, provider: provider, protocol: :native_chat, assume_model_exists: true)
           .with_provider_options(reasoning: 'off')
  end

  each_model(NATIVE_CHAT_MODELS) do |provider, model|
    it "#{provider}/#{model} can have a basic conversation" do
      response = native_chat(model, provider).ask("What's 2 + 2? Answer with just the number.")

      expect(response.content).to include('4')
      expect(response.role).to eq(:assistant)
      expect(response.tokens.input.to_i).to be_positive
      expect(response.tokens.output.to_i).to be_positive
    end

    it "#{provider}/#{model} continues a stored conversation across turns" do
      chat = native_chat(model, provider)

      first = chat.ask('My name is Dewayne. Reply with only: noted')
      expect(first.raw.body['response_id']).to start_with('resp_')

      second = chat.ask('What is my name? Answer with just the name.')
      expect(second.content).to include('Dewayne')
      expect(second.raw.env.request_body).to include(first.raw.body['response_id'])
    end

    it "#{provider}/#{model} supports streaming responses" do
      chunks = []
      response = native_chat(model, provider).ask('Count from 1 to 3') { |chunk| chunks << chunk }

      expect(chunks).not_to be_empty
      expect(chunks.map(&:content).join).to eq(response.content)
      expect(response.raw.body['response_id']).to start_with('resp_')
    end

    it "#{provider}/#{model} reports performance stats in the raw body" do
      response = native_chat(model, provider).ask("What's 2 + 2?")

      stats = response.raw.body['stats']
      expect(stats['tokens_per_second']).to be_positive
      expect(stats['time_to_first_token_seconds']).to be_positive
      expect(stats['input_tokens']).to eq(response.tokens.input)
    end
  end

  each_model(NATIVE_REASONING_MODELS) do |provider, model|
    it "#{provider}/#{model} separates reasoning from content" do
      chat = RubyLLM.chat(model: model, provider: provider, protocol: :native_chat, assume_model_exists: true)
                    .with_thinking(effort: :low)
      response = chat.ask('What is 2 + 2? Answer with just the number.')

      expect(response.content).to include('4')
      expect(response.thinking&.text).not_to be_nil
      expect(response.tokens.thinking.to_i).to be_positive
    end
  end
end
